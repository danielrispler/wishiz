// Package httpfetch is the static HTTP fetcher: it returns raw HTML + final URL
// + headers for the Engine to extract from. It carries the Chrome-TLS
// fingerprinting (utls) relocated from the retired fastpath scraper, plus a full
// Chrome header set, a UA rotation pool, a cookie jar, gzip/brotli decoding and
// retry/backoff on soft anti-bot responses. It re-validates every redirect hop
// through the SSRF guard. This defeats naive checks only — hard anti-bot
// (Cloudflare challenge/DataDome/Akamai/PerimeterX) still requires the render or
// the paid backstop.
package httpfetch

import (
	"compress/flate"
	"compress/gzip"
	"context"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/andybalholm/brotli"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/httpx"
)

const (
	requestTimeout = 10 * time.Second
	maxBodyBytes   = 8 << 20 // 8 MiB
	maxAttempts    = 3
	maxBackoff     = 4 * time.Second
	// maxClientRedirects bounds how many meta-refresh / JS-location hops Fetch
	// will follow (HTTP 3xx is handled separately by the transport).
	maxClientRedirects = 3
)

// clientRedirectPatterns detect a same-document redirect the HTTP layer can't
// see: a <meta http-equiv="refresh"> URL, or a top-level JS location assignment.
var clientRedirectPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)<meta[^>]+http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["'][^"']*?url\s*=\s*([^"'\s>]+)`),
	regexp.MustCompile(`(?i)window\.location(?:\.href)?\s*=\s*["']([^"']+)["']`),
	regexp.MustCompile(`(?i)location\.(?:href\s*=|replace\s*\(|assign\s*\()\s*["']([^"']+)["']`),
}

// Client is a static HTTP Fetcher.
type Client struct {
	client   *http.Client
	resolver scrapeapp.HostResolver
}

func New(resolver scrapeapp.HostResolver) *Client {
	jar, _ := cookiejar.New(nil)
	return &Client{
		client: &http.Client{
			Jar:       jar,
			Transport: httpx.NewUTLSTransport(requestTimeout),
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if err := scrapeapp.IsRedirectAllowed(req.Context(), resolver, req.URL.String()); err != nil {
					return err
				}
				if len(via) >= 10 {
					return fmt.Errorf("too many redirects")
				}
				return nil
			},
		},
		resolver: resolver,
	}
}

// Fetch retrieves the page and returns its raw HTML, final URL and headers,
// retrying soft anti-bot responses (403/429/503) with backoff and following
// client-side (meta-refresh / JS-location) redirects that the HTTP layer can't
// see, re-validating each hop through the SSRF guard.
func (c *Client) Fetch(ctx context.Context, rawURL string) (scrapeapp.FetchResult, error) {
	requestCtx, cancel := context.WithTimeout(ctx, requestTimeout)
	defer cancel()

	currentURL := rawURL
	for hop := 0; ; hop++ {
		result, err := c.fetchWithRetry(requestCtx, currentURL)
		if err != nil {
			return scrapeapp.FetchResult{}, err
		}
		if hop >= maxClientRedirects {
			return result, nil
		}
		target := clientRedirectTarget(result.HTML, result.FinalURL)
		if target == "" {
			return result, nil
		}
		// Re-validate the client-side hop exactly like an HTTP redirect; if it
		// isn't safe to follow, return what we already have rather than erroring.
		if err := scrapeapp.IsRedirectAllowed(requestCtx, c.resolver, target); err != nil {
			return result, nil
		}
		currentURL = target
	}
}

// fetchWithRetry performs one logical fetch of rawURL, retrying soft anti-bot
// responses (403/429/503) with backoff.
func (c *Client) fetchWithRetry(ctx context.Context, rawURL string) (scrapeapp.FetchResult, error) {
	var lastStatus int
	for attempt := 0; attempt < maxAttempts; attempt++ {
		result, status, retryAfter, err := c.attempt(ctx, rawURL)
		if err != nil {
			return scrapeapp.FetchResult{}, err
		}
		if status == http.StatusOK {
			return result, nil
		}
		lastStatus = status
		if !isRetryable(status) || attempt == maxAttempts-1 {
			break
		}
		if err := sleep(ctx, backoff(attempt, retryAfter)); err != nil {
			return scrapeapp.FetchResult{}, err
		}
	}
	return scrapeapp.FetchResult{}, fmt.Errorf("static fetch returned status %d", lastStatus)
}

func (c *Client) attempt(ctx context.Context, rawURL string) (scrapeapp.FetchResult, int, time.Duration, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, http.NoBody)
	if err != nil {
		return scrapeapp.FetchResult{}, 0, 0, err
	}
	setBrowserHeaders(request)

	response, err := c.client.Do(request)
	if err != nil {
		return scrapeapp.FetchResult{}, 0, 0, err
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return scrapeapp.FetchResult{}, response.StatusCode, retryAfter(response), nil
	}

	body, err := decodedBody(response)
	if err != nil {
		return scrapeapp.FetchResult{}, 0, 0, err
	}

	finalURL := rawURL
	if response.Request != nil && response.Request.URL != nil {
		finalURL = response.Request.URL.String()
	}
	return scrapeapp.FetchResult{
		FinalURL: finalURL,
		HTML:     string(body),
		Status:   response.StatusCode,
		Headers:  response.Header,
	}, response.StatusCode, 0, nil
}

func setBrowserHeaders(request *http.Request) {
	profile := nextProfile()
	header := request.Header
	header.Set("User-Agent", profile.userAgent)
	header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8")
	header.Set("Accept-Language", "en-US,en;q=0.9")
	header.Set("Accept-Encoding", "gzip, deflate, br")
	header.Set("sec-ch-ua", profile.secCHUA)
	header.Set("sec-ch-ua-mobile", profile.secCHUAMobile)
	header.Set("sec-ch-ua-platform", profile.secCHUAPlatform)
	header.Set("Sec-Fetch-Dest", "document")
	header.Set("Sec-Fetch-Mode", "navigate")
	header.Set("Sec-Fetch-Site", "none")
	header.Set("Sec-Fetch-User", "?1")
	header.Set("Upgrade-Insecure-Requests", "1")
	if origin := originOf(request.URL); origin != "" {
		header.Set("Referer", origin)
	}
}

func originOf(u *url.URL) string {
	if u == nil || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host + "/"
}

// decodedBody reads and decompresses the response body fully, then closes the
// decompressor so its integrity check runs (gzip's Close validates the CRC). We
// set Accept-Encoding manually so we can request brotli, which disables the
// transport's transparent gzip handling — we must decode ourselves. The
// Content-Encoding token is matched case-insensitively (e.g. "GZIP" is valid),
// and a decompression failure surfaces as an error rather than partial bytes
// being fed to the parser as plaintext.
func decodedBody(response *http.Response) ([]byte, error) {
	encoding := strings.ToLower(strings.TrimSpace(response.Header.Get("Content-Encoding")))

	var reader io.Reader = response.Body
	var closer io.Closer
	switch encoding {
	case "gzip":
		gz, err := gzip.NewReader(response.Body)
		if err != nil {
			return nil, err
		}
		reader, closer = gz, gz
	case "br":
		reader = brotli.NewReader(response.Body)
	case "deflate":
		fl := flate.NewReader(response.Body)
		reader, closer = fl, fl
	}

	body, err := io.ReadAll(io.LimitReader(reader, maxBodyBytes))
	if err != nil {
		return nil, err
	}
	if closer != nil {
		if err := closer.Close(); err != nil {
			return nil, err
		}
	}
	return body, nil
}

// clientRedirectTarget returns the absolute URL of a meta-refresh / JS-location
// redirect found in htmlBody, resolved against finalURL, or "" if there is none
// (or it points at the same page / a non-http(s) scheme).
func clientRedirectTarget(htmlBody, finalURL string) string {
	base, err := url.Parse(finalURL)
	if err != nil {
		return ""
	}
	for _, pattern := range clientRedirectPatterns {
		match := pattern.FindStringSubmatch(htmlBody)
		if match == nil {
			continue
		}
		target := html.UnescapeString(strings.TrimSpace(match[1]))
		if target == "" {
			continue
		}
		resolved, err := url.Parse(target)
		if err != nil {
			continue
		}
		absolute := base.ResolveReference(resolved)
		if absolute.Scheme != "http" && absolute.Scheme != "https" {
			continue
		}
		if absolute.String() == base.String() {
			continue
		}
		return absolute.String()
	}
	return ""
}

func isRetryable(status int) bool {
	return status == http.StatusForbidden ||
		status == http.StatusTooManyRequests ||
		status == http.StatusServiceUnavailable
}

func retryAfter(response *http.Response) time.Duration {
	value := response.Header.Get("Retry-After")
	if value == "" {
		return 0
	}
	if seconds, err := strconv.Atoi(value); err == nil {
		return time.Duration(seconds) * time.Second
	}
	if when, err := http.ParseTime(value); err == nil {
		if d := time.Until(when); d > 0 {
			return d
		}
	}
	return 0
}

// backoffBase is the exponential backoff unit (var so tests can shrink it).
var backoffBase = time.Second

func backoff(attempt int, retryAfter time.Duration) time.Duration {
	wait := time.Duration(1<<uint(attempt)) * backoffBase
	if retryAfter > wait {
		wait = retryAfter
	}
	if wait > maxBackoff {
		wait = maxBackoff
	}
	return wait
}

func sleep(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return nil
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

var _ scrapeapp.Fetcher = (*Client)(nil)
