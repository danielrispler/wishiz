package fastpath

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/PuerkitoBio/goquery"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

type Scraper struct {
	client   *http.Client
	resolver scrapeapp.HostResolver
}

func NewScraper(resolver scrapeapp.HostResolver) *Scraper {
	return &Scraper{
		client: &http.Client{
			Transport: http.DefaultTransport,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				ctx := req.Context()
				if err := scrapeapp.IsRedirectAllowed(ctx, resolver, req.URL); err != nil {
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

func (s *Scraper) Scrape(ctx context.Context, rawURL string) (scrapeapp.Product, error) {
	requestCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	currentURL := rawURL
	var lastProduct scrapeapp.Product

	for redirects := 0; redirects < 3; redirects++ {
		product, finalURL, body, err := s.fetchAndExtract(requestCtx, currentURL)
		if err != nil {
			return scrapeapp.Product{}, err
		}
		if product.IsComplete() {
			return product, nil
		}
		lastProduct = product

		redirectURL := clientRedirectURL(finalURL, body)
		if redirectURL == "" {
			return product, nil
		}
		parsedRedirect, err := url.Parse(redirectURL)
		if err != nil {
			return product, nil
		}
		if !parsedRedirect.IsAbs() {
			base, parseErr := url.Parse(finalURL)
			if parseErr != nil {
				return product, nil
			}
			parsedRedirect = base.ResolveReference(parsedRedirect)
		}
		if err := scrapeapp.IsRedirectAllowed(requestCtx, s.resolver, parsedRedirect); err != nil {
			return product, nil
		}
		currentURL = parsedRedirect.String()
	}

	return lastProduct, nil
}

func (s *Scraper) fetchAndExtract(ctx context.Context, rawURL string) (scrapeapp.Product, string, string, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, http.NoBody)
	if err != nil {
		return scrapeapp.Product{}, "", "", err
	}

	request.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	request.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	request.Header.Set("Accept-Language", "en-US,en;q=0.9")

	response, err := s.client.Do(request)
	if err != nil {
		return scrapeapp.Product{}, "", "", err
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusBadRequest {
		return scrapeapp.Product{}, "", "", fmt.Errorf("fast path returned status %d", response.StatusCode)
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return scrapeapp.Product{}, "", "", err
	}

	pageURL := rawURL
	if response.Request != nil && response.Request.URL != nil {
		pageURL = response.Request.URL.String()
	}

	bodyText := string(body)
	product, err := ExtractProduct(pageURL, bodyText)
	return product, pageURL, bodyText, err
}

func clientRedirectURL(pageURL string, html string) string {
	metaRedirect := metaRefreshRedirect(pageURL, html)
	if metaRedirect != "" {
		return metaRedirect
	}
	return javascriptRedirect(html)
}

func metaRefreshRedirect(pageURL string, html string) string {
	document, err := goquery.NewDocumentFromReader(strings.NewReader(html))
	if err != nil {
		return ""
	}

	var destination string
	document.Find(`meta[http-equiv]`).EachWithBreak(func(_ int, selection *goquery.Selection) bool {
		equiv, _ := selection.Attr("http-equiv")
		if !strings.EqualFold(strings.TrimSpace(equiv), "refresh") {
			return true
		}
		content, _ := selection.Attr("content")
		match := metaRefreshPattern.FindStringSubmatch(content)
		if len(match) < 2 {
			return true
		}
		destination = strings.TrimSpace(match[1])
		return false
	})
	if destination == "" {
		return ""
	}

	base, err := url.Parse(pageURL)
	if err != nil {
		return destination
	}
	parsed, err := url.Parse(destination)
	if err != nil {
		return destination
	}
	return base.ResolveReference(parsed).String()
}

func javascriptRedirect(html string) string {
	match := javascriptRedirectPattern.FindStringSubmatch(html)
	if len(match) < 2 {
		return ""
	}
	return strings.TrimSpace(match[1])
}

var metaRefreshPattern = regexp.MustCompile(`(?i)url\s*=\s*['"]?([^'";]+)`)
var javascriptRedirectPattern = regexp.MustCompile(`(?i)(?:window\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)['"]`)

var _ scrapeapp.Scraper = (*Scraper)(nil)
