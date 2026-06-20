package application

import (
	"context"
	"net/http"
)

// FetchResult is the raw output of a single fetch attempt. Extraction is NOT
// performed by the fetcher — the Service owns the Engine and extracts once over
// the raw HTML. This keeps extraction unit-testable from fixtures with no
// browser or network, and lets every fetch source (static HTTP, Shopify probe,
// headless render) feed the same consensus engine.
type FetchResult struct {
	// FinalURL is the URL after following redirects/meta-refresh/JS redirects.
	FinalURL string
	// HTML is the decoded page body (gzip/brotli already decompressed).
	HTML string
	// Status is the HTTP status of the final response (0 for render-only fetchers).
	Status int
	// Headers are the final response headers (used for Shopify detection, etc).
	Headers http.Header
}

// Fetcher retrieves a page and returns its raw HTML plus the final URL and
// headers. Implementations MUST re-validate every redirect/in-page hop through
// IsRedirectAllowed (SSRF guard) — see validate.go.
type Fetcher interface {
	Fetch(ctx context.Context, rawURL string) (FetchResult, error)
}
