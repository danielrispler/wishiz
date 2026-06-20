package headless

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/chromedp/cdproto/network"
	"github.com/chromedp/cdproto/page"
	"github.com/chromedp/chromedp"
	"github.com/chromedp/chromedp/device"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

const defaultRenderTimeout = 26 * time.Second

// stealthScript hides the most obvious automation tell (navigator.webdriver)
// before any page script runs. Soft hardening only.
const stealthScript = `Object.defineProperty(navigator, 'webdriver', {get: () => undefined});`

// Content-aware settling: after the body is visible we poll the DOM until a
// structured product signal appears (JSON-LD/microdata Product or a price meta)
// or the DOM stops changing, capped by settleMax. This restores the old
// poll-until-ready behavior that the blind fixed sleep regressed — JS-heavy SPA
// pages hydrate their price/JSON-LD after the body paints — without coupling the
// renderer to the extraction engine (the single-extraction contract).
const (
	minSettle        = 800 * time.Millisecond
	settlePoll       = 250 * time.Millisecond
	defaultSettleMax = 6 * time.Second
)

// Scraper is the headless-render Fetcher: it navigates a real Chromium, lets the
// page settle, and returns the rendered HTML + final URL for the Engine to
// extract from. It performs NO extraction itself (single-extraction contract).
type Scraper struct {
	allocatorCtx  context.Context
	cancel        context.CancelFunc
	resolver      scrapeapp.HostResolver
	renderTimeout time.Duration
	settleMax     time.Duration
}

func NewScraper(chromiumPath string, resolver scrapeapp.HostResolver, renderTimeout time.Duration) *Scraper {
	if renderTimeout <= 0 {
		renderTimeout = defaultRenderTimeout
	}
	options := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.Flag("headless", "new"),
		chromedp.Flag("no-sandbox", true),
		chromedp.Flag("disable-dev-shm-usage", true),
		chromedp.Flag("disable-gpu", true),
		chromedp.Flag("no-first-run", true),
		chromedp.Flag("no-default-browser-check", true),
		chromedp.Flag("disable-blink-features", "AutomationControlled"),
	)
	if chromiumPath != "" {
		options = append(options, chromedp.ExecPath(chromiumPath))
	}

	allocatorCtx, cancel := chromedp.NewExecAllocator(context.Background(), options...)

	settleMax := defaultSettleMax
	if settleMax > renderTimeout {
		settleMax = renderTimeout
	}

	return &Scraper{
		allocatorCtx:  allocatorCtx,
		cancel:        cancel,
		resolver:      resolver,
		renderTimeout: renderTimeout,
		settleMax:     settleMax,
	}
}

func (s *Scraper) Close() error {
	if s.cancel != nil {
		s.cancel()
	}
	return nil
}

// Fetch renders rawURL and returns the settled HTML + final URL. Honors ctx
// cancellation (the orchestrator's early-abort) and its own render sub-timeout.
func (s *Scraper) Fetch(ctx context.Context, rawURL string) (scrapeapp.FetchResult, error) {
	if err := ctx.Err(); err != nil {
		return scrapeapp.FetchResult{}, err
	}

	browserCtx, browserCancel := chromedp.NewContext(s.allocatorCtx)
	defer browserCancel()

	tabCtx, tabCancel := chromedp.NewContext(browserCtx)
	defer tabCancel()

	requestCtx, requestCancel := context.WithTimeout(tabCtx, s.renderTimeout)
	defer requestCancel()
	stopParentCancel := context.AfterFunc(ctx, requestCancel)
	defer stopParentCancel()

	runCtx, cancelRun := context.WithCancelCause(requestCtx)
	defer cancelRun(nil)
	chromedp.ListenTarget(runCtx, func(event any) {
		request, ok := event.(*network.EventRequestWillBeSent)
		if !ok || request == nil || request.Request.URL == "" {
			return
		}
		if err := s.validateRequestedURL(runCtx, request.Request.URL); err != nil {
			cancelRun(err)
		}
	})

	var (
		pageURL = rawURL
		html    string
	)
	err := chromedp.Run(runCtx,
		network.Enable(),
		chromedp.Emulate(device.IPhone13ProMax),
		chromedp.ActionFunc(func(ctx context.Context) error {
			_, err := page.AddScriptToEvaluateOnNewDocument(stealthScript).Do(ctx)
			return err
		}),
		chromedp.Navigate(rawURL),
		chromedp.WaitVisible("body", chromedp.ByQuery),
		chromedp.ActionFunc(func(ctx context.Context) error {
			return s.settle(ctx, &pageURL, &html)
		}),
	)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			if cause := context.Cause(runCtx); cause != nil && !errors.Is(cause, context.Canceled) {
				return scrapeapp.FetchResult{}, cause
			}
		}
		return scrapeapp.FetchResult{}, err
	}

	return scrapeapp.FetchResult{FinalURL: pageURL, HTML: html}, nil
}

// settle polls the rendered DOM until a structured product signal appears or the
// DOM stops growing, capped by settleMax. It always waits minSettle first so very
// fast pages still give late JS a beat to run. The latest location + outerHTML
// are written through to the caller on every poll, so whatever is present when we
// stop is what gets extracted.
func (s *Scraper) settle(ctx context.Context, pageURL *string, html *string) error {
	if err := sleepCtx(ctx, minSettle); err != nil {
		return err
	}
	deadline := time.Now().Add(s.settleMax)
	prevLen := -1
	for {
		if err := chromedp.Location(pageURL).Do(ctx); err != nil {
			return err
		}
		if err := chromedp.OuterHTML("html", html, chromedp.ByQuery).Do(ctx); err != nil {
			return err
		}
		if htmlHasProductSignal(*html) {
			return nil
		}
		length := len(*html)
		if length > 0 && length == prevLen {
			return nil // DOM stabilized — nothing more is hydrating
		}
		prevLen = length
		if time.Now().After(deadline) {
			return nil
		}
		if err := sleepCtx(ctx, settlePoll); err != nil {
			return err
		}
	}
}

// htmlHasProductSignal reports whether the rendered HTML already carries
// structured product data — JSON-LD/microdata Product or an explicit price meta.
// Generic OpenGraph title/image is deliberately NOT a signal: almost every shell
// page has it, so it would stop settling before the real data hydrates.
func htmlHasProductSignal(html string) bool {
	lower := strings.ToLower(html)
	if strings.Contains(lower, "application/ld+json") && strings.Contains(lower, `"product"`) {
		return true
	}
	if strings.Contains(lower, "product:price:amount") || strings.Contains(lower, "og:price:amount") {
		return true
	}
	if strings.Contains(lower, "schema.org/product") {
		return true
	}
	return false
}

func sleepCtx(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func (s *Scraper) validateRequestedURL(ctx context.Context, rawURL string) error {
	return scrapeapp.IsBrowserSubresourceAllowed(ctx, s.resolver, rawURL)
}

var _ scrapeapp.Fetcher = (*Scraper)(nil)
