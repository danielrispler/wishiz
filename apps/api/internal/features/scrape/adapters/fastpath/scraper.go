package fastpath

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

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

	request, err := http.NewRequestWithContext(requestCtx, http.MethodGet, rawURL, http.NoBody)
	if err != nil {
		return scrapeapp.Product{}, err
	}

	request.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	request.Header.Set("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	request.Header.Set("Accept-Language", "en-US,en;q=0.9")

	response, err := s.client.Do(request)
	if err != nil {
		return scrapeapp.Product{}, err
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusBadRequest {
		return scrapeapp.Product{}, fmt.Errorf("fast path returned status %d", response.StatusCode)
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return scrapeapp.Product{}, err
	}

	pageURL := rawURL
	if response.Request != nil && response.Request.URL != nil {
		pageURL = response.Request.URL.String()
	}

	return ExtractProduct(pageURL, string(body))
}

var _ scrapeapp.Scraper = (*Scraper)(nil)
