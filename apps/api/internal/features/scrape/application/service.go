package application

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/url"
	"sync"
	"sync/atomic"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

const (
	defaultBudget          = 30 * time.Second
	defaultMaxRenders      = 3
	defaultStaticTimeout   = 10 * time.Second
	defaultBackstopTimeout = 30 * time.Second
)

// CandidateSource is a network source that contributes candidates directly
// (e.g. the Shopify product-JSON probe). It runs concurrently with the fetchers.
type CandidateSource interface {
	Candidates(ctx context.Context, pageURL string) ([]extractors.Candidate, error)
}

// ServiceConfig tunes the orchestrator.
type ServiceConfig struct {
	Budget               time.Duration // total wall-clock budget (default 30s)
	MaxConcurrentRenders int           // render semaphore size (default 3)
	// Backstop is the optional paid last-resort fetcher (ZenRows). Nil disables the
	// import second pass — every path then behaves exactly as without it.
	Backstop Backstop
	// BackstopTimeout bounds the backstop fetch. It is applied ON TOP of Budget
	// (derived from the inbound ctx, not the budget ctx), so a 30s budget + 30s
	// backstop is a 60s worst case. Zero falls back to defaultBackstopTimeout.
	BackstopTimeout time.Duration
}

// Service runs ONE best-effort pipeline per scrape: static HTTP fetch + Shopify
// probe + headless render all launch concurrently; the expensive render is
// early-aborted once the cheap sources already clear the verdict gate. It owns
// the Engine and extracts once over each source's HTML.
type Service struct {
	logger          *slog.Logger
	engine          *Engine
	static          Fetcher
	render          Fetcher
	probe           CandidateSource
	resolver        HostResolver
	converter       PriceConverter
	budget          time.Duration
	renderSem       chan struct{}
	backstop        Backstop
	backstopTimeout time.Duration
}

func NewService(
	logger *slog.Logger,
	engine *Engine,
	static Fetcher,
	render Fetcher,
	probe CandidateSource,
	resolver HostResolver,
	converter PriceConverter,
	cfg ServiceConfig,
) *Service {
	if logger == nil {
		logger = slog.Default()
	}
	if engine == nil {
		engine = NewEngine(EngineConfig{})
	}
	if resolver == nil {
		resolver = net.DefaultResolver
	}
	if converter == nil {
		converter = IdentityPriceConverter{}
	}
	if cfg.Budget <= 0 {
		cfg.Budget = defaultBudget
	}
	if cfg.MaxConcurrentRenders <= 0 {
		cfg.MaxConcurrentRenders = defaultMaxRenders
	}
	if cfg.BackstopTimeout <= 0 {
		cfg.BackstopTimeout = defaultBackstopTimeout
	}
	return &Service{
		logger:          logger,
		engine:          engine,
		static:          static,
		render:          render,
		probe:           probe,
		resolver:        resolver,
		converter:       converter,
		budget:          cfg.Budget,
		renderSem:       make(chan struct{}, cfg.MaxConcurrentRenders),
		backstop:        cfg.Backstop,
		backstopTimeout: cfg.BackstopTimeout,
	}
}

// Scrape runs the pipeline with no progress reporting and no paid backstop. Used
// by discover and the synchronous /scrape route — neither pays for ZenRows.
func (s *Service) Scrape(ctx context.Context, rawURL string, targetCurrencyCode string) (Product, error) {
	return s.scrape(ctx, rawURL, targetCurrencyCode, nil, false)
}

// ScrapeWithProgress runs the pipeline and emits progress to reporter (nil ok),
// without the paid backstop.
func (s *Service) ScrapeWithProgress(
	ctx context.Context,
	rawURL string,
	targetCurrencyCode string,
	reporter ProgressReporter,
) (Product, error) {
	return s.scrape(ctx, rawURL, targetCurrencyCode, reporter, false)
}

// ScrapeImport runs the pipeline for a user-initiated product import: it reports
// progress AND, when configured, fires the paid ZenRows backstop as a last resort
// on a non-auto_complete outcome. Only the product-import worker calls this — the
// backstop never runs for discover or the synchronous /scrape route.
func (s *Service) ScrapeImport(
	ctx context.Context,
	rawURL string,
	targetCurrencyCode string,
	reporter ProgressReporter,
) (Product, error) {
	return s.scrape(ctx, rawURL, targetCurrencyCode, reporter, true)
}

func (s *Service) scrape(
	ctx context.Context,
	rawURL string,
	targetCurrencyCode string,
	reporter ProgressReporter,
	enableBackstop bool,
) (Product, error) {
	targetCurrency, err := NormalizeCurrencyCode(targetCurrencyCode)
	if err != nil {
		return Product{}, err
	}
	validatedURL, err := NormalizeProductURL(ctx, s.resolver, rawURL)
	if err != nil {
		return Product{}, err
	}
	reporter.report(StageValidating, percentValidating)

	budgetCtx, cancel := context.WithTimeout(ctx, s.budget)
	defer cancel()

	pageURL := validatedURL.String()
	startedAt := time.Now()

	var (
		mu      sync.Mutex
		all     []extractors.Candidate
		blocked atomic.Bool
	)
	noteHTML := func(html string) {
		if IsAntiBotBlock(html) {
			blocked.Store(true)
		}
	}
	add := func(candidates []extractors.Candidate) {
		if len(candidates) == 0 {
			return
		}
		mu.Lock()
		all = append(all, candidates...)
		mu.Unlock()
	}
	snapshot := func() []extractors.Candidate {
		mu.Lock()
		defer mu.Unlock()
		return append([]extractors.Candidate(nil), all...)
	}

	renderCtx, cancelRender := context.WithCancel(budgetCtx)
	defer cancelRender()

	var cheapWG, renderWG sync.WaitGroup

	// Cheap source: static HTTP fetch → extract.
	if s.static != nil {
		cheapWG.Add(1)
		go func() {
			defer cheapWG.Done()
			result, fetchErr := s.static.Fetch(budgetCtx, pageURL)
			if fetchErr != nil {
				s.logger.Debug("static fetch failed", "url", pageURL, "error", fetchErr.Error())
				return
			}
			noteHTML(result.HTML)
			add(s.engine.Extract(result.HTML, finalURLOr(result.FinalURL, pageURL), result.Headers))
		}()
	}

	// Cheap source: Shopify product-JSON probe.
	if s.probe != nil {
		cheapWG.Add(1)
		go func() {
			defer cheapWG.Done()
			candidates, probeErr := s.probe.Candidates(budgetCtx, pageURL)
			if probeErr != nil {
				s.logger.Debug("shopify probe failed", "url", pageURL, "error", probeErr.Error())
				return
			}
			add(candidates)
		}()
	}

	// Strongest source: headless render (cancellable via early-abort).
	if s.render != nil {
		renderWG.Add(1)
		go func() {
			defer renderWG.Done()
			select {
			case s.renderSem <- struct{}{}:
				defer func() { <-s.renderSem }()
			case <-renderCtx.Done():
				return
			}
			reporter.report(StageRendering, percentRendering)
			result, renderErr := s.render.Fetch(renderCtx, pageURL)
			if renderErr != nil {
				s.logger.Debug("headless render failed", "url", pageURL, "error", renderErr.Error())
				return
			}
			reporter.report(StagePageLoaded, percentPageLoaded)
			noteHTML(result.HTML)
			add(s.engine.Extract(result.HTML, finalURLOr(result.FinalURL, pageURL), result.Headers))
		}()
	}

	// Early-abort: reconcile the cheap-source candidates ONCE. If they already
	// clear the verdict gate, keep that captured result and cancel the render —
	// reconciling a second time after the wait could fold in render candidates
	// that landed between the gate snapshot and the wait, yielding a different
	// verdict for the same page. If the gate didn't clear, wait for the render
	// and reconcile once over the full candidate set. One reconcile per outcome.
	cheapWG.Wait()
	reporter.report(StageExtracting, percentExtracting)
	product := s.engine.Reconcile(snapshot(), pageURL)
	if product.Verdict == VerdictAutoComplete {
		cancelRender()
	} else {
		renderWG.Wait()
		product = s.engine.Reconcile(snapshot(), pageURL)
	}
	renderWG.Wait()

	if enableBackstop && s.backstop != nil && product.Verdict != VerdictAutoComplete {
		proxyCountry := inferProxyCountry(validatedURL.Hostname())
		product = s.applyBackstop(ctx, reporter, product, proxyCountry, pageURL, noteHTML, add, snapshot)
	}

	reporter.report(StageCrossChecking, percentCrossChecking)
	product = s.applyConversion(product, targetCurrency)

	if !product.HasAnyData() {
		if errors.Is(budgetCtx.Err(), context.DeadlineExceeded) {
			return product, Timeout("scrape timed out")
		}
		if blocked.Load() {
			return product, Unsupported("this store blocks automatic import")
		}
		return product, ScrapeFailed("could not extract product details")
	}

	reporter.report(StageDone, percentDone)
	s.logger.Info(
		"scrape completed",
		"url", pageURL,
		"verdict", string(product.Verdict),
		"duration_ms", time.Since(startedAt).Milliseconds(),
	)
	return product, nil
}

// applyBackstop runs the paid ZenRows second pass: ONE residential-proxy fetch
// (its timeout is ON TOP of the scrape budget — bsCtx is derived from the inbound
// ctx, NOT budgetCtx). For Amazon hosts (incl. a.co/amzn.* shorteners) it uses
// autoparse (structured JSON) — Amazon serves no JSON-LD/og tags so the HTML
// extractors find no trusted price; every other host uses the rendered-HTML pass.
// Either way the new candidates fold into the same consensus, re-reconcile, and
// the verdict-floor guard keeps the result only when it does not lower the verdict
// (a geo-priced exit can never degrade the outcome). Any ZenRows error soft-fails
// (logged, never retried — a settled job re-enters only via user Retry, ADR-0001).
func (s *Service) applyBackstop(
	ctx context.Context,
	reporter ProgressReporter,
	product Product,
	proxyCountry string,
	pageURL string,
	noteHTML func(string),
	add func([]extractors.Candidate),
	snapshot func() []extractors.Candidate,
) Product {
	reporter.report(StageBackstop, percentBackstop)
	bsCtx, bsCancel := context.WithTimeout(ctx, s.backstopTimeout)
	defer bsCancel()

	// Amazon: autoparse first. Fall through to the HTML pass when it errors or maps
	// nothing (schema-drift safety).
	if extractors.IsAmazonHost(hostOf(pageURL)) {
		if rescued, handled := s.applyAutoparseBackstop(bsCtx, product, pageURL, proxyCountry, add, snapshot); handled {
			return rescued
		}
	}
	return s.applyHTMLBackstop(bsCtx, product, proxyCountry, pageURL, noteHTML, add, snapshot)
}

// applyAutoparseBackstop runs the ZenRows autoparse pass for Amazon hosts. It
// returns handled=false (the caller falls through to the HTML pass) when the fetch
// errors or maps no candidates; otherwise handled=true with the re-reconciled,
// verdict-floor-guarded product. Currency is resolved from the ZenRows final-URL
// host (the shortener is unwrapped by then), never guessed (ADR-0006).
func (s *Service) applyAutoparseBackstop(
	ctx context.Context,
	product Product,
	pageURL, proxyCountry string,
	add func([]extractors.Candidate),
	snapshot func() []extractors.Candidate,
) (Product, bool) {
	res, err := s.backstop.FetchAutoparse(ctx, pageURL, proxyCountry)
	if err != nil {
		s.logger.Warn("zenrows autoparse failed", "url", pageURL, "error", err.Error())
		return product, false
	}
	finalURL := finalURLOr(res.FinalURL, pageURL)
	base, _ := url.Parse(finalURL)
	candidates := extractors.MapAutoparseProduct(res.JSON, hostOf(finalURL), base)
	if len(candidates) == 0 {
		s.logger.Info("zenrows autoparse mapped nothing; falling back to HTML", "url", pageURL)
		return product, false
	}

	add(candidates)
	rescued := s.engine.Reconcile(snapshot(), pageURL)
	if verdictRank(rescued.Verdict) < verdictRank(product.Verdict) {
		s.logger.Info(
			"zenrows autoparse discarded (would degrade verdict)",
			"url", pageURL, "own", string(product.Verdict), "backstop", string(rescued.Verdict),
		)
		return product, true
	}
	s.logger.Info(
		"zenrows backstop applied", "url", pageURL, "mode", "autoparse", "verdict", string(rescued.Verdict),
	)
	return rescued, true
}

// applyHTMLBackstop runs the rendered-HTML ZenRows pass: its HTML feeds the same
// Extract → consensus → verdict path as every other source (transport, not a
// source). Verdict-floor-guarded; any error soft-fails to the own product.
func (s *Service) applyHTMLBackstop(
	ctx context.Context,
	product Product,
	proxyCountry, pageURL string,
	noteHTML func(string),
	add func([]extractors.Candidate),
	snapshot func() []extractors.Candidate,
) Product {
	result, err := s.backstop.Fetch(ctx, pageURL, proxyCountry)
	if err != nil {
		s.logger.Warn("zenrows backstop failed", "url", pageURL, "error", err.Error())
		return product
	}

	noteHTML(result.HTML)
	add(s.engine.Extract(result.HTML, finalURLOr(result.FinalURL, pageURL), result.Headers))
	candidate := s.engine.Reconcile(snapshot(), pageURL)
	if verdictRank(candidate.Verdict) < verdictRank(product.Verdict) {
		s.logger.Info(
			"zenrows backstop discarded (would degrade verdict)",
			"url", pageURL, "own", string(product.Verdict), "backstop", string(candidate.Verdict),
		)
		return product
	}
	s.logger.Info("zenrows backstop applied", "url", pageURL, "mode", "html", "verdict", string(candidate.Verdict))
	return candidate
}

// applyConversion converts the price to the target currency. On failure it keeps
// the original amount+currency, flags it, and forces the product into review
// (never fails the whole product over a missing exchange rate).
func (s *Service) applyConversion(product Product, targetCurrency string) Product {
	if product.PriceAmount == "" || product.PriceCurrency == "" {
		return product
	}
	fromCurrency := product.PriceCurrency
	amount, currency, err := s.converter.Convert(product.PriceAmount, fromCurrency, targetCurrency)
	if err != nil {
		product.PriceWarnings = uniqueStrings(append(product.PriceWarnings, extractors.WarningCurrencyUnconverted))
		// Keep the legacy price-confidence string below "trusted" for the
		// no-verdict fallback path (HasTrustedPrice).
		if product.PriceConfidence == PriceConfidenceHigh {
			product.PriceConfidence = PriceConfidenceMedium
		}
		product.Verdict, product.Reasons = ComputeVerdict(product)
		// A price we could not convert to the target currency must never
		// auto-complete: the amount is correct but it is in the wrong currency for
		// display. Force review even when every field is otherwise high-confidence.
		// (Under the relaxed gate a MEDIUM downgrade would still auto-complete, so
		// the override — not a confidence downgrade — is what holds it for review.)
		if product.Verdict == VerdictAutoComplete {
			product.Verdict = VerdictNeedsReview
			product.Reasons = append(product.Reasons, extractors.WarningCurrencyUnconverted)
		}
		return product
	}
	product.PriceAmount = amount
	product.PriceCurrency = currency
	// Convert the range high bound with the SAME from/to as the low bound. If only
	// the max fails to convert, drop it (show the converted low as a single price)
	// rather than failing the item — the low already converted fine, so the item is
	// still useful. A low-bound failure is handled above (force review).
	if product.PriceAmountMax != "" {
		if maxAmount, _, maxErr := s.converter.Convert(product.PriceAmountMax, fromCurrency, targetCurrency); maxErr == nil {
			product.PriceAmountMax = maxAmount
		} else {
			product.PriceAmountMax = ""
		}
	}
	// Recompute the verdict for symmetry with the failure branch: the price field
	// changed, so the verdict must be derived from the post-conversion product.
	product.Verdict, product.Reasons = ComputeVerdict(product)
	return product
}

func finalURLOr(finalURL, fallback string) string {
	if finalURL == "" {
		return fallback
	}
	return finalURL
}
