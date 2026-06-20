//go:build scrapelive

// Package eval's live acceptance tests hit the real retail sites end-to-end
// through the production scraper wiring (static httpfetch + shopify probe +
// headless render). They are gated behind the `scrapelive` build tag because
// they require network access and a local Chromium/Chrome.
//
//	go test -tags scrapelive -run Live -v ./internal/features/scrape/eval/
//
// These reproduce the regression where JS-heavy SPA retail pages returned no
// data. The pipeline must handle them generically — there is deliberately NO
// per-host logic here or in the engine. A site that hard-blocks automated
// access (Akamai/Cloudflare "Access Denied" before any JS) is reported via
// t.Skip, not a failure: no in-process code change can extract it without a
// paid backstop, and we do not want to special-case a fake pass.
package eval

import (
	"context"
	"log/slog"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	scrapeheadless "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/headless"
	scrapehttpfetch "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/httpfetch"
	scrapeshopify "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/shopify"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

func newHeadless() *scrapeheadless.Scraper {
	return scrapeheadless.NewScraper("", net.DefaultResolver, 26*time.Second)
}

func newLiveService(t *testing.T, headless *scrapeheadless.Scraper) *scrapeapp.Service {
	t.Helper()
	resolver := net.DefaultResolver
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelDebug}))

	static := scrapehttpfetch.New(resolver)
	probe := scrapeshopify.NewProbe(resolver)
	engine := scrapeapp.NewEngine(scrapeapp.EngineConfig{})

	return scrapeapp.NewService(
		logger, engine, static, headless, probe, resolver, nil,
		scrapeapp.ServiceConfig{Budget: 30 * time.Second},
	)
}

func TestLiveRetailScrape(t *testing.T) {
	cases := []struct {
		name string
		url  string
	}{
		{"aritzia", "https://www.aritzia.com/us/en/product/the-lodge-pant™/118269.html?color=36213"},
		{"crateandbarrel", "https://www.crateandbarrel.com/unwind-modular-4-piece-slipcovered-reversible-sectional-sofa-with-ottoman/s360865"},
		{"westelm", "https://www.westelm.com/products/norre-media-console-h6983/?cm_src=consoles-media-storage-cabinets"},
	}

	headless := newHeadless()
	defer func() { _ = headless.Close() }()
	svc := newLiveService(t, headless)

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
			defer cancel()

			product, err := svc.Scrape(ctx, tc.url, "USD")
			t.Logf("verdict=%q name=%q image=%q price=%q %s reasons=%v err=%v",
				product.Verdict, product.Name, product.ImageURL,
				product.PriceAmount, product.PriceCurrency, product.Reasons, err)
			t.Logf("fields: name=%s price=%s currency=%s image=%s",
				product.Fields.Name, product.Fields.Price,
				product.Fields.Currency, product.Fields.Image)

			usable := err == nil &&
				product.Verdict != scrapeapp.VerdictFailed &&
				product.Name != "" && product.ImageURL != "" && product.PriceAmount != ""
			if usable {
				return
			}

			// Not usable — classify. A recognized hard anti-bot block is an
			// external limitation (needs a paid backstop), not an extraction
			// regression, so skip rather than fail.
			if blocked, why := antiBotBlocked(headless, tc.url); blocked {
				t.Skipf("site blocks automated access (%s) — needs paid backstop / stealth browser, not an in-process fix", why)
			}
			t.Fatalf("no usable data and not a recognized anti-bot block: verdict=%q name=%q image=%q price=%q",
				product.Verdict, product.Name, product.ImageURL, product.PriceAmount)
		})
	}
}

// antiBotBlocked renders the URL directly and reports whether the response is a
// recognized hard anti-bot block page (tiny body + a known block phrase).
func antiBotBlocked(headless *scrapeheadless.Scraper, url string) (bool, string) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	res, err := headless.Fetch(ctx, url)
	if err != nil {
		return false, ""
	}
	body := strings.TrimSpace(res.HTML)
	if len(body) > 4000 { // real product pages are large; block pages are tiny
		return false, ""
	}
	lower := strings.ToLower(body)
	for _, phrase := range []string{
		"access denied", "reference #", "pardon our interruption",
		"are you a robot", "captcha", "request blocked", "attention required",
	} {
		if strings.Contains(lower, phrase) {
			return true, phrase
		}
	}
	return false, ""
}
