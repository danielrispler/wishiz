package application

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
)

func TestServiceFallsBackToHeadlessWhenFastIsIncomplete(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name: "Nike Shox TL",
			}, nil
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:          "Nike Shox TL",
				PriceAmount:   "599.90",
				PriceCurrency: "ILS",
				ImageURL:      "https://example.com/nike.png",
			}, nil
		}},
		stubResolver{},
	)

	product, err := service.Scrape(context.Background(), "https://www.nike.com/product")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if product.Source != sourceHeadless {
		t.Fatalf("expected headless source, got %q", product.Source)
	}
}

func TestServiceRejectsPrivateHosts(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{},
		stubScraper{},
		stubResolver{},
	)

	_, err := service.Scrape(context.Background(), "http://127.0.0.1/private")
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeBadRequest {
		t.Fatalf("expected bad request error, got %v", err)
	}
}

func TestServiceReturnsScrapeFailureWhenBothPathsHaveNoUsableData(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{}, errors.New("blocked")
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{}, nil
		}},
		stubResolver{},
	)

	_, err := service.Scrape(context.Background(), "https://example.com/product")
	if err == nil {
		t.Fatalf("expected scrape failure")
	}

	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeScrape {
		t.Fatalf("expected scrape failure, got %v", err)
	}
}

func TestServiceReturnsPartialProductWhenSomeDataExists(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name: "חולצת פולו מכותנה Loose Fit",
			}, nil
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:     "חולצת פולו מכותנה Loose Fit",
				ImageURL: "https://image.hm.com/product.jpg",
			}, nil
		}},
		stubResolver{},
	)

	product, err := service.Scrape(context.Background(), "https://www2.hm.com/product")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if product.Name != "חולצת פולו מכותנה Loose Fit" || product.ImageURL == "" || product.Source != sourceHeadless {
		t.Fatalf("unexpected partial product: %+v", product)
	}
}

type stubScraper struct {
	scrape func(ctx context.Context, rawURL string) (Product, error)
}

func (s stubScraper) Scrape(ctx context.Context, rawURL string) (Product, error) {
	if s.scrape == nil {
		return Product{}, nil
	}
	return s.scrape(ctx, rawURL)
}
