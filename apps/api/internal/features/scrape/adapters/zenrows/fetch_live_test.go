//go:build scrapelive

package zenrows

import (
	"context"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// TestZenRowsFetchLive hits the real ZenRows Universal Scraper API. It is skipped
// unless ZENROWS_API_KEY is set, mirroring httpfetch/fingerprint_live_test.go.
//
// Run: ZENROWS_API_KEY=… go test -tags scrapelive -run ZenRows \
//   ./internal/features/scrape/adapters/zenrows/
func TestZenRowsFetchLive(t *testing.T) {
	apiKey := os.Getenv("ZENROWS_API_KEY")
	if apiKey == "" {
		t.Skip("ZENROWS_API_KEY not set")
	}

	client := New(apiKey, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()

	result, err := client.Fetch(ctx, "https://httpbin.org/html", "")
	if err != nil {
		t.Fatalf("live ZenRows fetch failed: %v", err)
	}
	if result.HTML == "" {
		t.Fatal("expected non-empty rendered HTML")
	}
}

// TestZenRowsAutoparseLive proves the Amazon rescue end-to-end against the real
// ZenRows API: an a.co short link resolves to an amazon.* final URL, autoparse
// returns structured JSON, and the mapper yields a name + USD price candidate.
// Skipped without ZENROWS_API_KEY. Also logs X-Request-Cost so we can confirm
// whether autoparse adds any surcharge over js_render+premium_proxy (ADR-0006).
//
// Run: ZENROWS_API_KEY=… go test -tags scrapelive -run ZenRows \
//   ./internal/features/scrape/adapters/zenrows/
func TestZenRowsAutoparseLive(t *testing.T) {
	apiKey := os.Getenv("ZENROWS_API_KEY")
	if apiKey == "" {
		t.Skip("ZENROWS_API_KEY not set")
	}
	shortLink := os.Getenv("ZENROWS_AUTOPARSE_URL")
	if shortLink == "" {
		// A stable Amazon US ASIN; override via env when it goes out of stock.
		shortLink = "https://www.amazon.com/dp/B0B64RSCCV"
	}

	client := New(apiKey, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	res, err := client.FetchAutoparse(ctx, shortLink, "")
	if err != nil {
		t.Fatalf("live autoparse fetch failed: %v", err)
	}
	if len(res.JSON) == 0 {
		t.Fatal("expected non-empty autoparse JSON")
	}
	t.Logf("final_url=%s cost=%s", res.FinalURL, res.Headers.Get("X-Request-Cost"))

	host := strings.ToLower(res.FinalURL)
	if !strings.Contains(host, "amazon.") {
		t.Fatalf("final URL %q is not an amazon marketplace", res.FinalURL)
	}

	base, _ := url.Parse(res.FinalURL)
	candidates := extractors.MapAutoparseProduct(res.JSON, hostnameOf(res.FinalURL), base)
	if _, ok := candidateField(candidates, extractors.FieldName); !ok {
		t.Fatalf("autoparse mapped no name; JSON head: %.300s", res.JSON)
	}
	if price, ok := candidateField(candidates, extractors.FieldPrice); !ok || price.Currency == "" {
		t.Fatalf("autoparse mapped no priced candidate; JSON head: %.300s", res.JSON)
	}
}

func hostnameOf(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return u.Hostname()
}

func candidateField(candidates []extractors.Candidate, field extractors.Field) (extractors.Candidate, bool) {
	for _, c := range candidates {
		if c.Field == field {
			return c, true
		}
	}
	return extractors.Candidate{}, false
}
