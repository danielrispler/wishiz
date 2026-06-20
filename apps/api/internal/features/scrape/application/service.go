package application

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"sync"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

const (
	defaultBudget        = 30 * time.Second
	defaultMaxRenders    = 3
	defaultStaticTimeout = 10 * time.Second
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
}

// Service runs ONE best-effort pipeline per scrape: static HTTP fetch + Shopify
// probe + headless render all launch concurrently; the expensive render is
// early-aborted once the cheap sources already clear the verdict gate. It owns
// the Engine and extracts once over each source's HTML.
type Service struct {
	logger    *slog.Logger
	engine    *Engine
	static    Fetcher
	render    Fetcher
	probe     CandidateSource
	resolver  HostResolver
	converter PriceConverter
	budget    time.Duration
	renderSem chan struct{}
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
	return &Service{
		logger:    logger,
		engine:    engine,
		static:    static,
		render:    render,
		probe:     probe,
		resolver:  resolver,
		converter: converter,
		budget:    cfg.Budget,
		renderSem: make(chan struct{}, cfg.MaxConcurrentRenders),
	}
}

// Scrape satisfies the productimports Scraper port (no progress reporting).
func (s *Service) Scrape(ctx context.Context, rawURL string, targetCurrencyCode string) (Product, error) {
	return s.ScrapeWithProgress(ctx, rawURL, targetCurrencyCode, nil)
}

// ScrapeWithProgress runs the pipeline and emits progress to reporter (nil ok).
func (s *Service) ScrapeWithProgress(
	ctx context.Context,
	rawURL string,
	targetCurrencyCode string,
	reporter ProgressReporter,
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
		mu  sync.Mutex
		all []extractors.Candidate
	)
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
			add(s.engine.Extract(result.HTML, finalURLOr(result.FinalURL, pageURL), result.Headers))
		}()
	}

	// Early-abort: as soon as the cheap sources clear the verdict gate, cancel
	// the render so it returns immediately instead of running the full budget.
	cheapWG.Wait()
	reporter.report(StageExtracting, percentExtracting)
	if s.engine.Reconcile(snapshot(), pageURL).Verdict == VerdictAutoComplete {
		cancelRender()
	}
	renderWG.Wait()

	reporter.report(StageCrossChecking, percentCrossChecking)
	product := s.engine.Reconcile(snapshot(), pageURL)
	product = s.applyConversion(product, targetCurrency)

	if !product.HasAnyData() {
		if errors.Is(budgetCtx.Err(), context.DeadlineExceeded) {
			return product, Timeout("scrape timed out")
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

// applyConversion converts the price to the target currency. On failure it keeps
// the original amount+currency, flags it, and downgrades the price below
// auto-complete (never fails the whole product over a missing exchange rate).
func (s *Service) applyConversion(product Product, targetCurrency string) Product {
	if product.PriceAmount == "" || product.PriceCurrency == "" {
		return product
	}
	amount, currency, err := s.converter.Convert(product.PriceAmount, product.PriceCurrency, targetCurrency)
	if err != nil {
		product.PriceWarnings = uniqueStrings(append(product.PriceWarnings, extractors.WarningCurrencyUnconverted))
		if product.Fields.Price == ConfidenceHigh {
			product.Fields.Price = ConfidenceMedium
			product.PriceConfidence = legacyPriceConfidence(product.Fields.Price)
		}
		product.Verdict, product.Reasons = ComputeVerdict(product)
		return product
	}
	product.PriceAmount = amount
	product.PriceCurrency = currency
	return product
}

func finalURLOr(finalURL, fallback string) string {
	if finalURL == "" {
		return fallback
	}
	return finalURL
}
