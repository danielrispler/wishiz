package headless

import (
	"context"
	"errors"
	"time"

	"github.com/chromedp/cdproto/network"
	"github.com/chromedp/chromedp"
	"github.com/chromedp/chromedp/device"

	fastpath "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/fastpath"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

type Scraper struct {
	allocatorCtx context.Context
	cancel       context.CancelFunc
	resolver     scrapeapp.HostResolver
}

func NewScraper(chromiumPath string, resolver scrapeapp.HostResolver) *Scraper {
	options := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.Flag("headless", "new"),
		chromedp.Flag("no-sandbox", true),
		chromedp.Flag("disable-dev-shm-usage", true),
		chromedp.Flag("disable-gpu", true),
		chromedp.Flag("no-first-run", true),
		chromedp.Flag("no-default-browser-check", true),
	)
	if chromiumPath != "" {
		options = append(options, chromedp.ExecPath(chromiumPath))
	}

	allocatorCtx, cancel := chromedp.NewExecAllocator(context.Background(), options...)

	return &Scraper{
		allocatorCtx: allocatorCtx,
		cancel:       cancel,
		resolver:     resolver,
	}
}

func (s *Scraper) Close() error {
	if s.cancel != nil {
		s.cancel()
	}
	return nil
}

func (s *Scraper) Scrape(ctx context.Context, rawURL string) (scrapeapp.Product, error) {
	if err := ctx.Err(); err != nil {
		return scrapeapp.Product{}, err
	}

	browserCtx, browserCancel := chromedp.NewContext(s.allocatorCtx)
	defer browserCancel()

	tabCtx, tabCancel := chromedp.NewContext(browserCtx)
	defer tabCancel()

	requestCtx, requestCancel := context.WithTimeout(tabCtx, 30*time.Second)
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

	pageURL := rawURL
	var html string

	err := chromedp.Run(runCtx,
		network.Enable(),
		chromedp.Emulate(device.IPhone13ProMax),
		chromedp.Navigate(rawURL),
		chromedp.WaitVisible("body", chromedp.ByQuery),
		chromedp.ActionFunc(func(ctx context.Context) error {
			deadline := time.Now().Add(3 * time.Second)
			for {
				if err := chromedp.Location(&pageURL).Do(ctx); err != nil {
					return err
				}
				if err := chromedp.OuterHTML("html", &html, chromedp.ByQuery).Do(ctx); err != nil {
					return err
				}
				product, err := fastpath.ExtractProduct(pageURL, html)
				if err == nil && product.IsComplete() {
					return nil
				}
				if time.Now().After(deadline) {
					return nil
				}
				select {
				case <-ctx.Done():
					return ctx.Err()
				case <-time.After(200 * time.Millisecond):
				}
			}
		}),
	)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			if cause := context.Cause(runCtx); cause != nil && !errors.Is(cause, context.Canceled) {
				return scrapeapp.Product{}, cause
			}
		}
		return scrapeapp.Product{}, err
	}

	return fastpath.ExtractProduct(pageURL, html)
}

func (s *Scraper) validateRequestedURL(ctx context.Context, rawURL string) error {
	return scrapeapp.IsRedirectAllowed(ctx, s.resolver, rawURL)
}

var _ scrapeapp.Scraper = (*Scraper)(nil)
