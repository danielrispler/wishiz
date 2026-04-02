package scrapehttp

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

func TestScrapeRouteReturnsProductJSON(t *testing.T) {
	t.Parallel()

	service := stubService{
		scrape: func(_ context.Context, rawURL string) (scrapeapp.Product, error) {
			if rawURL != "https://example.com/product" {
				t.Fatalf("unexpected url %q", rawURL)
			}
			return scrapeapp.Product{
				Name:          "Nike Shox TL",
				PriceAmount:   "599.90",
				PriceCurrency: "ILS",
				ImageURL:      "https://example.com/image.png",
				Source:        "headless",
			}, nil
		},
	}

	mux := http.NewServeMux()
	RegisterRoutes(mux, testLogger(), service)

	request := httptest.NewRequest(http.MethodGet, "/scrape?url=https://example.com/product", http.NoBody)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", recorder.Code, recorder.Body.String())
	}

	var payload scrapeapp.Product
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Name != "Nike Shox TL" || payload.PriceCurrency != "ILS" {
		t.Fatalf("unexpected payload: %+v", payload)
	}
}

func TestScrapeRouteReturnsValidationError(t *testing.T) {
	t.Parallel()

	service := stubService{
		scrape: func(context.Context, string) (scrapeapp.Product, error) {
			return scrapeapp.Product{}, scrapeapp.BadRequest("url is required")
		},
	}

	mux := http.NewServeMux()
	RegisterRoutes(mux, testLogger(), service)

	request := httptest.NewRequest(http.MethodGet, "/scrape", http.NoBody)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", recorder.Code)
	}
}

func TestScrapeRouteReturnsTimeout(t *testing.T) {
	t.Parallel()

	service := stubService{
		scrape: func(ctx context.Context, _ string) (scrapeapp.Product, error) {
			<-ctx.Done()
			return scrapeapp.Product{}, ctx.Err()
		},
	}

	mux := http.NewServeMux()
	h := handler{
		logger:  testLogger(),
		service: service,
		timeout: 5 * time.Millisecond,
	}
	mux.HandleFunc("GET /scrape", h.scrapeProduct)

	request := httptest.NewRequest(http.MethodGet, "/scrape?url=https://example.com/product", http.NoBody)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusGatewayTimeout {
		t.Fatalf("expected 504, got %d with body %s", recorder.Code, recorder.Body.String())
	}
}

type stubService struct {
	scrape func(ctx context.Context, rawURL string) (scrapeapp.Product, error)
}

func (s stubService) Scrape(ctx context.Context, rawURL string) (scrapeapp.Product, error) {
	return s.scrape(ctx, rawURL)
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}
