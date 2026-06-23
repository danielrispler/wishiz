//go:build scrapelive

package zenrows

import (
	"context"
	"os"
	"testing"
	"time"
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
