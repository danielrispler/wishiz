// Package zenrows implements the paid last-resort backstop fetcher. When the own
// scrape pipeline cannot auto-complete a product — JS-challenge / datacenter-IP
// reputation blocks that our Chrome-fingerprinted static fetcher cannot beat
// (Cloudflare challenge, DataDome, Akamai, PerimeterX) — the Service makes ONE
// ZenRows Universal Scraper API call: a residential proxy + headless render we
// cannot run ourselves.
//
// ZenRows owns the browser fingerprint, so this client is a plain net/http GET —
// no tls-client. Its rendered HTML feeds the SAME Extract → consensus → verdict
// path as every other source: ZenRows is a transport, not an extraction source,
// so it adds no SourceName and needs no migration.
package zenrows

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

// defaultBaseURL is the ZenRows Universal Scraper API endpoint.
const defaultBaseURL = "https://api.zenrows.com/v1/"

// maxBodyBytes caps a rendered page body (defensive; pages are well under this).
const maxBodyBytes = 8 << 20 // 8 MiB

// Client fetches a page through ZenRows. The fetch is time-bounded by the caller's
// context (the Service derives a ZENROWS_TIMEOUT-bounded ctx), so the http.Client
// has no Timeout of its own.
type Client struct {
	apiKey     string
	baseURL    string
	httpClient *http.Client
	logger     *slog.Logger
}

// New builds a ZenRows client. A nil logger falls back to slog.Default().
func New(apiKey string, logger *slog.Logger) *Client {
	if logger == nil {
		logger = slog.Default()
	}
	return &Client{apiKey: apiKey, baseURL: defaultBaseURL, httpClient: &http.Client{}, logger: logger}
}

// Fetch renders rawURL via ZenRows with js_render + premium_proxy (the 25× full-
// power mode — justified because it only fires as a last resort). proxyCountry
// pins the residential exit to an ISO 3166-1 alpha-2 country when non-empty; ""
// leaves the exit to ZenRows. A non-200 response is returned as an error so the
// Service can soft-fail to the own-pipeline product.
func (c *Client) Fetch(ctx context.Context, rawURL, proxyCountry string) (scrapeapp.FetchResult, error) {
	query := c.baseQuery(rawURL, proxyCountry)
	body, finalURL, header, err := c.do(ctx, query, rawURL)
	if err != nil {
		return scrapeapp.FetchResult{}, err
	}
	c.logger.Info(
		"zenrows fetch ok",
		"url", rawURL, "final_url", finalURL, "proxy_country", proxyCountry,
		"cost", header.Get("X-Request-Cost"),
	)
	return scrapeapp.FetchResult{
		FinalURL: finalURL,
		HTML:     string(body),
		Status:   http.StatusOK,
		Headers:  header,
	}, nil
}

// FetchAutoparse renders rawURL via ZenRows with autoparse=true (on top of
// js_render + premium_proxy), returning the structured-product JSON instead of
// HTML. Used for the Amazon rescue (ADR-0006): Amazon serves no JSON-LD/og tags,
// so our HTML extractors find no trusted price — ZenRows' own parser does. Any
// non-200 is returned as an error so the Service can soft-fail / fall back.
func (c *Client) FetchAutoparse(
	ctx context.Context, rawURL, proxyCountry string,
) (scrapeapp.AutoparseResult, error) {
	query := c.baseQuery(rawURL, proxyCountry)
	query.Set("autoparse", "true")
	body, finalURL, header, err := c.do(ctx, query, rawURL)
	if err != nil {
		return scrapeapp.AutoparseResult{}, err
	}
	c.logger.Info(
		"zenrows autoparse fetch ok",
		"url", rawURL, "final_url", finalURL, "proxy_country", proxyCountry,
		"cost", header.Get("X-Request-Cost"),
	)
	return scrapeapp.AutoparseResult{
		FinalURL: finalURL,
		JSON:     body,
		Status:   http.StatusOK,
		Headers:  header,
	}, nil
}

// baseQuery builds the shared ZenRows query: full-power js_render + premium_proxy
// (the 25× last-resort mode), optionally pinning the residential exit country.
func (c *Client) baseQuery(rawURL, proxyCountry string) url.Values {
	query := url.Values{}
	query.Set("apikey", c.apiKey)
	query.Set("url", rawURL)
	query.Set("js_render", "true")
	query.Set("premium_proxy", "true")
	if proxyCountry != "" {
		query.Set("proxy_country", proxyCountry)
	}
	return query
}

// do issues the ZenRows GET and returns the (capped) body, the resolved final URL
// (Zr-Final-Url, falling back to rawURL), and the response headers. A non-200 is
// an error so callers soft-fail.
func (c *Client) do(
	ctx context.Context, query url.Values, rawURL string,
) (body []byte, finalURL string, header http.Header, err error) {
	endpoint, err := url.Parse(c.baseURL)
	if err != nil {
		return nil, "", nil, fmt.Errorf("parse zenrows base url: %w", err)
	}
	endpoint.RawQuery = query.Encode()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), http.NoBody)
	if err != nil {
		return nil, "", nil, fmt.Errorf("build zenrows request: %w", err)
	}

	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, "", nil, fmt.Errorf("zenrows request: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		// 402 no-credits / 429 account concurrency / 422 unprocessable / 5xx. All
		// soft-fail upstream; surface the code so the rescue-miss is observable.
		return nil, "", nil, fmt.Errorf("zenrows status %d", response.StatusCode)
	}

	body, err = io.ReadAll(io.LimitReader(response.Body, maxBodyBytes))
	if err != nil {
		return nil, "", nil, fmt.Errorf("read zenrows body: %w", err)
	}

	finalURL = response.Header.Get("Zr-Final-Url")
	if finalURL == "" {
		finalURL = rawURL
	}
	return body, finalURL, response.Header, nil
}

var _ scrapeapp.Backstop = (*Client)(nil)
