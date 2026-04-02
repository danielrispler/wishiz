package headless

import (
	"context"
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
}

func NewScraper(chromiumPath string) *Scraper {
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
	}
}

func (s *Scraper) Close() error {
	if s.cancel != nil {
		s.cancel()
	}
	return nil
}

func (s *Scraper) Scrape(ctx context.Context, rawURL string) (scrapeapp.Product, error) {
	browserCtx, browserCancel := chromedp.NewContext(s.allocatorCtx)
	defer browserCancel()

	tabCtx, tabCancel := chromedp.NewContext(browserCtx)
	defer tabCancel()

	requestCtx, requestCancel := context.WithTimeout(tabCtx, 30*time.Second)
	defer requestCancel()

	var html string

	err := chromedp.Run(requestCtx,
		network.Enable(),
		chromedp.Emulate(device.IPhone13ProMax),
		chromedp.Navigate(rawURL),
		chromedp.WaitVisible("body", chromedp.ByQuery),
		chromedp.Sleep(2*time.Second),
		chromedp.OuterHTML("html", &html, chromedp.ByQuery),
	)
	if err != nil {
		return scrapeapp.Product{}, err
	}

	return fastpath.ExtractProduct(rawURL, html)
}

var _ scrapeapp.Scraper = (*Scraper)(nil)
