// Package httpfetch is the static HTTP fetcher: it returns raw HTML + final URL
// + headers for the Engine to extract from. It uses bogdanfinn/tls-client +
// fhttp to present a COMPLETE Chrome fingerprint — JA3/JA4 (TLS) AND the HTTP/2
// layer (SETTINGS, header + pseudo-header order) — keyed off httpx.ChromeProfile
// and aligned to the UA rotation pool, plus a full Chrome header set, a cookie
// jar, gzip/brotli decoding and retry/backoff on soft anti-bot responses. It
// follows HTTP 3xx and meta-refresh/JS-location hops itself, re-validating every
// hop through the SSRF guard. This defeats naive + fingerprint checks only —
// hard anti-bot (Cloudflare challenge/DataDome/Akamai/PerimeterX, datacenter-IP
// reputation) still requires the render or the paid backstop.
package httpfetch

import (
	"compress/flate"
	"compress/gzip"
	"context"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/andybalholm/brotli"
	fhttp "github.com/bogdanfinn/fhttp"
	tls_client "github.com/bogdanfinn/tls-client"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/httpx"
)

// requestTimeout bounds a whole Fetch (all hops + retries). It is a var so tests
// can shrink it.
var requestTimeout = 10 * time.Second

const (
	maxBodyBytes = 8 << 20 // 8 MiB
	maxAttempts  = 3
	maxBackoff   = 4 * time.Second
	// maxClientRedirects bounds meta-refresh / JS-location hops Fetch follows.
	maxClientRedirects = 3
	// maxHTTPRedirects bounds HTTP 3xx hops a single attempt follows. Distinct
	// from maxClientRedirects (client-side, in-page redirects).
	maxHTTPRedirects = 10
)

// chromeHeaderOrder is Chrome's request header order for a top-level navigation.
// fhttp emits the headers it has in this order (it is part of the HTTP/2
// fingerprint); names are lowercase as the wire format requires.
var chromeHeaderOrder = []string{
	"sec-ch-ua",
	"sec-ch-ua-mobile",
	"sec-ch-ua-platform",
	"upgrade-insecure-requests",
	"user-agent",
	"accept",
	"sec-fetch-site",
	"sec-fetch-mode",
	"sec-fetch-user",
	"sec-fetch-dest",
	"referer",
	"accept-encoding",
	"accept-language",
	"cookie",
}

// chromePseudoHeaderOrder is Chrome's HTTP/2 pseudo-header order.
var chromePseudoHeaderOrder = []string{":method", ":authority", ":scheme", ":path"}

// clientRedirectPatterns detect a same-document redirect the HTTP layer can't
// see: a <meta http-equiv="refresh"> URL, or a top-level JS location assignment.
var clientRedirectPatterns = []*regexp.Regexp{
	regexp.MustCompile(`(?i)<meta[^>]+http-equiv\s*=\s*["']?refresh["']?[^>]*content\s*=\s*["'][^"']*?url\s*=\s*([^"'\s>]+)`),
	regexp.MustCompile(`(?i)window\.location(?:\.href)?\s*=\s*["']([^"']+)["']`),
	regexp.MustCompile(`(?i)location\.(?:href\s*=|replace\s*\(|assign\s*\()\s*["']([^"']+)["']`),
}

// Client is a static HTTP Fetcher.
type Client struct {
	resolver scrapeapp.HostResolver
	// validateHop re-validates a redirect target through the SSRF guard before it
	// is followed. A field (defaulting to the real guard) so tests can exercise
	// redirect-following against a loopback server the guard would otherwise block.
	validateHop func(ctx context.Context, target string) error
}

func New(resolver scrapeapp.HostResolver) *Client {
	return &Client{
		resolver: resolver,
		validateHop: func(ctx context.Context, target string) error {
			return scrapeapp.IsRedirectAllowed(ctx, resolver, target)
		},
	}
}

// Fetch retrieves the page and returns its raw HTML, final URL and headers,
// retrying soft anti-bot responses (403/429/503) with backoff, following HTTP
// 3xx and client-side (meta-refresh / JS-location) redirects, re-validating each
// hop through the SSRF guard. One tls-client (with its own cookie jar) is built
// per Fetch and reused across all hops, so cookies carry hop→hop while distinct
// scrapes stay isolated. The whole Fetch is bounded by requestTimeout.
func (c *Client) Fetch(ctx context.Context, rawURL string) (scrapeapp.FetchResult, error) {
	requestCtx, cancel := context.WithTimeout(ctx, requestTimeout)
	defer cancel()

	client, err := httpx.NewChromeClient(requestTimeout)
	if err != nil {
		return scrapeapp.FetchResult{}, err
	}
	defer client.CloseIdleConnections()

	// One profile per Fetch so the UA stays consistent across the redirect chain
	// (and consistent with the fixed Chrome TLS/HTTP-2 fingerprint).
	profile := nextProfile()

	currentURL := rawURL
	for clientHop := 0; ; clientHop++ {
		result, err := c.fetchWithRetry(requestCtx, client, profile, currentURL)
		if err != nil {
			return scrapeapp.FetchResult{}, err
		}
		if clientHop >= maxClientRedirects {
			return result, nil
		}
		target := clientRedirectTarget(result.HTML, result.FinalURL)
		if target == "" {
			return result, nil
		}
		// Re-validate the client-side hop exactly like an HTTP redirect; if it
		// isn't safe to follow, return what we already have rather than erroring.
		if err := c.validateHop(requestCtx, target); err != nil {
			return result, nil
		}
		currentURL = target
	}
}

// fetchWithRetry performs one logical fetch of rawURL (following HTTP 3xx),
// retrying soft anti-bot responses (403/429/503) with backoff.
func (c *Client) fetchWithRetry(
	ctx context.Context,
	client tls_client.HttpClient,
	profile browserProfile,
	rawURL string,
) (scrapeapp.FetchResult, error) {
	var lastStatus int
	for attempt := 0; attempt < maxAttempts; attempt++ {
		result, status, retryAfter, err := c.attempt(ctx, client, profile, rawURL)
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

// attempt performs one fetch of rawURL, following HTTP 3xx redirects up to
// maxHTTPRedirects and re-validating each Location through the SSRF guard (an
// HTTP 3xx to a disallowed target is a hard error, matching the old transport's
// CheckRedirect). It returns the final non-redirect response.
func (c *Client) attempt(
	ctx context.Context,
	client tls_client.HttpClient,
	profile browserProfile,
	rawURL string,
) (scrapeapp.FetchResult, int, time.Duration, error) {
	currentURL := rawURL
	for httpHop := 0; ; httpHop++ {
		request, err := fhttp.NewRequestWithContext(ctx, http.MethodGet, currentURL, fhttp.NoBody)
		if err != nil {
			return scrapeapp.FetchResult{}, 0, 0, err
		}
		setBrowserHeaders(request, profile)

		response, err := client.Do(request)
		if err != nil {
			return scrapeapp.FetchResult{}, 0, 0, err
		}

		if location := redirectLocation(response); location != "" {
			_ = response.Body.Close()
			if httpHop >= maxHTTPRedirects {
				return scrapeapp.FetchResult{}, 0, 0, fmt.Errorf("too many redirects")
			}
			next, locErr := resolveLocation(currentURL, location)
			if locErr != nil {
				return scrapeapp.FetchResult{}, 0, 0, locErr
			}
			if hopErr := c.validateHop(ctx, next); hopErr != nil {
				return scrapeapp.FetchResult{}, 0, 0, hopErr
			}
			currentURL = next
			continue
		}

		if response.StatusCode != http.StatusOK {
			status, retryWait := response.StatusCode, retryAfter(response.Header)
			_ = response.Body.Close()
			return scrapeapp.FetchResult{}, status, retryWait, nil
		}

		body, err := decodedBody(encodingOf(response.Header), response.Body)
		_ = response.Body.Close()
		if err != nil {
			return scrapeapp.FetchResult{}, 0, 0, err
		}
		return scrapeapp.FetchResult{
			FinalURL: currentURL,
			HTML:     string(body),
			Status:   response.StatusCode,
			Headers:  toStdHeader(response.Header),
		}, response.StatusCode, 0, nil
	}
}

// redirectLocation returns the Location of an HTTP 3xx redirect response, or ""
// when the response is not a redirect (or carries no Location).
func redirectLocation(response *fhttp.Response) string {
	switch response.StatusCode {
	case http.StatusMovedPermanently, http.StatusFound, http.StatusSeeOther,
		http.StatusTemporaryRedirect, http.StatusPermanentRedirect:
		return strings.TrimSpace(response.Header.Get("Location"))
	default:
		return ""
	}
}

// resolveLocation resolves a (possibly relative) Location against the current
// URL, requiring an http(s) result.
func resolveLocation(currentURL, location string) (string, error) {
	base, err := url.Parse(currentURL)
	if err != nil {
		return "", err
	}
	target, err := url.Parse(strings.TrimSpace(location))
	if err != nil {
		return "", err
	}
	absolute := base.ResolveReference(target)
	if absolute.Scheme != "http" && absolute.Scheme != "https" {
		return "", fmt.Errorf("redirect to non-http scheme %q", absolute.Scheme)
	}
	return absolute.String(), nil
}

func setBrowserHeaders(request *fhttp.Request, profile browserProfile) {
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
	// Header order is part of the Chrome fingerprint.
	header[fhttp.HeaderOrderKey] = chromeHeaderOrder
	header[fhttp.PHeaderOrderKey] = chromePseudoHeaderOrder
}

func originOf(u *url.URL) string {
	if u == nil || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host + "/"
}

// toStdHeader converts fhttp response headers to net/http.Header (the type
// FetchResult.Headers carries), dropping fhttp's header-order magic keys and
// canonicalizing names so downstream Get() calls resolve.
func toStdHeader(header fhttp.Header) http.Header {
	out := make(http.Header, len(header))
	for key, values := range header {
		if key == fhttp.HeaderOrderKey || key == fhttp.PHeaderOrderKey {
			continue
		}
		out[http.CanonicalHeaderKey(key)] = values
	}
	return out
}

func encodingOf(header fhttp.Header) string {
	return strings.ToLower(strings.TrimSpace(header.Get("Content-Encoding")))
}

// decodedBody reads and decompresses the response body fully, then closes the
// decompressor so its integrity check runs (gzip's Close validates the CRC). We
// set Accept-Encoding manually so we can request brotli, which disables any
// transparent gzip handling — we decode ourselves. The Content-Encoding token is
// matched case-insensitively (encodingOf lower-cases it), and a decompression
// failure surfaces as an error rather than partial bytes being fed to the parser
// as plaintext.
func decodedBody(encoding string, body io.Reader) ([]byte, error) {
	reader := body
	var closer io.Closer
	switch encoding {
	case "gzip":
		gz, err := gzip.NewReader(body)
		if err != nil {
			return nil, err
		}
		reader, closer = gz, gz
	case "br":
		reader = brotli.NewReader(body)
	case "deflate":
		fl := flate.NewReader(body)
		reader, closer = fl, fl
	}

	decoded, err := io.ReadAll(io.LimitReader(reader, maxBodyBytes))
	if err != nil {
		return nil, err
	}
	if closer != nil {
		if err := closer.Close(); err != nil {
			return nil, err
		}
	}
	return decoded, nil
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

func retryAfter(header fhttp.Header) time.Duration {
	value := header.Get("Retry-After")
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
