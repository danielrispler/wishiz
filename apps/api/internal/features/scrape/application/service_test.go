package application

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"testing"
	"time"
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
				Name:            "Nike Shox TL",
				PriceAmount:     "599.90",
				PriceCurrency:   "ILS",
				PriceConfidence: PriceConfidenceHigh,
				ImageURL:        "https://example.com/nike.png",
			}, nil
		}},
		stubResolver{},
		nil,
	)

	product, err := service.Scrape(context.Background(), "https://www.nike.com/product", "ILS")
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
		nil,
	)

	_, err := service.Scrape(context.Background(), "http://127.0.0.1/private", "ILS")
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
		nil,
	)

	_, err := service.Scrape(context.Background(), "https://example.com/product", "ILS")
	if err == nil {
		t.Fatalf("expected scrape failure")
	}

	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeScrape {
		t.Fatalf("expected scrape failure, got %v", err)
	}
}

func TestServiceFailsWhenBothPathsAreIncomplete(t *testing.T) {
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
		nil,
	)

	_, err := service.Scrape(context.Background(), "https://www2.hm.com/product", "ILS")
	if err == nil {
		t.Fatalf("expected scrape failure")
	}

	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeScrape {
		t.Fatalf("expected scrape failure, got %v", err)
	}
}

func TestServiceReturnsConvertedFastResultWithoutHeadless(t *testing.T) {
	t.Parallel()

	headlessCalled := false
	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:            "Sneakers",
				PriceAmount:     "100.00",
				PriceCurrency:   "USD",
				PriceConfidence: PriceConfidenceHigh,
				ImageURL:        "https://example.com/sneakers.png",
			}, nil
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			headlessCalled = true
			return Product{}, nil
		}},
		stubResolver{},
		stubConverter{amount: "360.00", currency: "ILS"},
	)

	product, err := service.Scrape(context.Background(), "https://example.com/product", "ILS")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if headlessCalled {
		t.Fatalf("expected fast result to skip headless")
	}
	if product.PriceAmount != "360.00" || product.PriceCurrency != "ILS" || product.Source != sourceFast {
		t.Fatalf("unexpected converted product: %+v", product)
	}
}

func TestServiceAppliesFifteenSecondScrapeDeadline(t *testing.T) {
	t.Parallel()

	var remaining time.Duration
	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(ctx context.Context, _ string) (Product, error) {
			deadline, ok := ctx.Deadline()
			if !ok {
				t.Fatalf("expected scrape deadline")
			}
			remaining = time.Until(deadline)
			return Product{
				Name:            "Sneakers",
				PriceAmount:     "100.00",
				PriceCurrency:   "USD",
				PriceConfidence: PriceConfidenceHigh,
				ImageURL:        "https://example.com/sneakers.png",
			}, nil
		}},
		stubScraper{},
		stubResolver{},
		nil,
	)

	_, err := service.Scrape(context.Background(), "https://example.com/product", "USD")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if remaining < 14*time.Second || remaining > defaultScrapeTimeout {
		t.Fatalf("expected about %s remaining, got %s", defaultScrapeTimeout, remaining)
	}
}

func TestServiceReturnsTimeoutWhenScrapeDeadlineExpires(t *testing.T) {
	t.Parallel()

	headlessCalled := false
	parentCtx, cancel := context.WithTimeout(context.Background(), time.Millisecond)
	defer cancel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(ctx context.Context, _ string) (Product, error) {
			<-ctx.Done()
			return Product{Name: "Slow product"}, ctx.Err()
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			headlessCalled = true
			return Product{}, nil
		}},
		stubResolver{},
		nil,
	)

	_, err := service.Scrape(parentCtx, "https://example.com/product", "USD")
	if err == nil {
		t.Fatalf("expected timeout error")
	}
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeTimeout {
		t.Fatalf("expected timeout error, got %v", err)
	}
	if headlessCalled {
		t.Fatalf("expected headless scrape to be skipped after timeout")
	}
}

func TestServiceFallsBackToHeadlessWhenFastPriceIsNotHighConfidence(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:            "Sneakers",
				PriceAmount:     "10.00",
				PriceCurrency:   "USD",
				PriceConfidence: PriceConfidenceSuspicious,
				ImageURL:        "https://example.com/fast.png",
			}, nil
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:            "Sneakers",
				PriceAmount:     "100.00",
				PriceCurrency:   "USD",
				PriceConfidence: PriceConfidenceHigh,
				ImageURL:        "https://example.com/headless.png",
			}, nil
		}},
		stubResolver{},
		nil,
	)

	product, err := service.Scrape(context.Background(), "https://example.com/product", "USD")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if product.Source != sourceHeadless || product.PriceAmount != "100.00" {
		t.Fatalf("expected high-confidence headless product, got %+v", product)
	}
}

func TestServiceReturnsBestCompleteProductWhenPriceNeedsReview(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:            "Sneakers",
				PriceAmount:     "10.00",
				PriceCurrency:   "USD",
				PriceConfidence: PriceConfidenceSuspicious,
				ImageURL:        "https://example.com/fast.png",
			}, nil
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{}, nil
		}},
		stubResolver{},
		nil,
	)

	product, err := service.Scrape(context.Background(), "https://example.com/product", "USD")
	if err != nil {
		t.Fatalf("expected reviewable product response, got %v", err)
	}
	if product.PriceConfidence != PriceConfidenceSuspicious || product.Source != sourceFast {
		t.Fatalf("unexpected product: %+v", product)
	}
}

func TestServiceFallsBackWhenFastConversionFails(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:          "Sneakers",
				PriceAmount:   "100.00",
				PriceCurrency: "USD",
				ImageURL:      "https://example.com/fast.png",
			}, nil
		}},
		stubScraper{scrape: func(context.Context, string) (Product, error) {
			return Product{
				Name:            "Sneakers",
				PriceAmount:     "320.00",
				PriceCurrency:   "ILS",
				PriceConfidence: PriceConfidenceHigh,
				ImageURL:        "https://example.com/headless.png",
			}, nil
		}},
		stubResolver{},
		stubConverter{failFrom: "USD"},
	)

	product, err := service.Scrape(context.Background(), "https://example.com/product", "ILS")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if product.PriceAmount != "320.00" || product.PriceCurrency != "ILS" || product.ImageURL != "https://example.com/headless.png" || product.Source != sourceHeadless {
		t.Fatalf("unexpected product: %+v", product)
	}
}

func TestServiceNormalizesGoogleURLBeforeScraping(t *testing.T) {
	t.Parallel()

	var scrapedURL string
	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		stubScraper{scrape: func(_ context.Context, rawURL string) (Product, error) {
			scrapedURL = rawURL
			return Product{
				Name:            "Jacket",
				PriceAmount:     "80.00",
				PriceCurrency:   "USD",
				PriceConfidence: PriceConfidenceHigh,
				ImageURL:        "https://merchant.example/jacket.png",
			}, nil
		}},
		stubScraper{},
		stubResolver{},
		nil,
	)

	_, err := service.Scrape(
		context.Background(),
		"https://www.google.com/url?q=https%3A%2F%2Fmerchant.example%2Fproducts%2Fjacket",
		"USD",
	)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if scrapedURL != "https://merchant.example/products/jacket" {
		t.Fatalf("expected merchant URL, got %q", scrapedURL)
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

type stubConverter struct {
	amount   string
	currency string
	failFrom string
}

func (s stubConverter) Convert(amount string, fromCurrency string, toCurrency string) (string, string, error) {
	if s.failFrom != "" && fromCurrency == s.failFrom {
		return "", "", fmt.Errorf("conversion failed")
	}
	if fromCurrency == toCurrency {
		return amount, toCurrency, nil
	}
	return s.amount, s.currency, nil
}
