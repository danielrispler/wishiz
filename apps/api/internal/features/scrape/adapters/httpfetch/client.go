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
	"io"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"strconv"
	"time"

	"github.com/andybalholm/brotli"
	utls "github.com/refraction-networking/utls"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

const (
	requestTimeout = 10 * time.Second
	maxBodyBytes   = 8 << 20 // 8 MiB
	maxAttempts    = 3
	maxBackoff     = 4 * time.Second
)

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
			Transport: newUTLSTransport(),
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
// retrying soft anti-bot responses (403/429/503) with backoff.
func (c *Client) Fetch(ctx context.Context, rawURL string) (scrapeapp.FetchResult, error) {
	requestCtx, cancel := context.WithTimeout(ctx, requestTimeout)
	defer cancel()

	var lastStatus int
	for attempt := 0; attempt < maxAttempts; attempt++ {
		result, status, retryAfter, err := c.attempt(requestCtx, rawURL)
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
		if err := sleep(requestCtx, backoff(attempt, retryAfter)); err != nil {
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

	reader, err := decodedBody(response)
	if err != nil {
		return scrapeapp.FetchResult{}, 0, 0, err
	}
	body, err := io.ReadAll(io.LimitReader(reader, maxBodyBytes))
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

// decodedBody wraps the response body with the right decompressor. We set
// Accept-Encoding manually (so we can request brotli), which disables the
// transport's transparent gzip handling — we must decode ourselves.
func decodedBody(response *http.Response) (io.Reader, error) {
	switch response.Header.Get("Content-Encoding") {
	case "gzip":
		return gzip.NewReader(response.Body)
	case "br":
		return brotli.NewReader(response.Body), nil
	case "deflate":
		return flate.NewReader(response.Body), nil
	default:
		return response.Body, nil
	}
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

// newUTLSTransport dials TLS with a Chrome fingerprint (utls) to dodge naive
// TLS-fingerprint blocks, pinned to HTTP/1.1 for goquery-friendly responses.
func newUTLSTransport() *http.Transport {
	return &http.Transport{
		ForceAttemptHTTP2: false,
		DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			conn, err := (&net.Dialer{Timeout: requestTimeout}).DialContext(ctx, network, addr)
			if err != nil {
				return nil, err
			}
			host, _, _ := net.SplitHostPort(addr)
			uConn := utls.UClient(conn, &utls.Config{ServerName: host}, utls.HelloChrome_Auto)
			if err := uConn.BuildHandshakeState(); err != nil {
				conn.Close()
				return nil, err
			}
			for _, ext := range uConn.Extensions {
				if alpn, ok := ext.(*utls.ALPNExtension); ok {
					alpn.AlpnProtocols = []string{"http/1.1"}
					break
				}
			}
			if err := uConn.HandshakeContext(ctx); err != nil {
				conn.Close()
				return nil, err
			}
			return uConn, nil
		},
	}
}

var _ scrapeapp.Fetcher = (*Client)(nil)
