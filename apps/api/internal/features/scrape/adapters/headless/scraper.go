package headless

import (
	"context"
	"errors"
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

// settleDelay is a short wait after the body is visible to let client-side JS
// populate prices/SPA content before we snapshot the DOM.
const settleDelay = 1500 * time.Millisecond

// Scraper is the headless-render Fetcher: it navigates a real Chromium, lets the
// page settle, and returns the rendered HTML + final URL for the Engine to
// extract from. It performs NO extraction itself (single-extraction contract).
type Scraper struct {
	allocatorCtx  context.Context
	cancel        context.CancelFunc
	resolver      scrapeapp.HostResolver
	renderTimeout time.Duration
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

	return &Scraper{
		allocatorCtx:  allocatorCtx,
		cancel:        cancel,
		resolver:      resolver,
		renderTimeout: renderTimeout,
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
		chromedp.Sleep(settleDelay),
		chromedp.Location(&pageURL),
		chromedp.OuterHTML("html", &html, chromedp.ByQuery),
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

func (s *Scraper) validateRequestedURL(ctx context.Context, rawURL string) error {
	return scrapeapp.IsRedirectAllowed(ctx, s.resolver, rawURL)
}

var _ scrapeapp.Fetcher = (*Scraper)(nil)
