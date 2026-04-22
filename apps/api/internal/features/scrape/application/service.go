package application

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"time"
)

const (
	sourceFast     = "fast"
	sourceHeadless = "headless"
)

type Service struct {
	logger    *slog.Logger
	fast      Scraper
	headless  Scraper
	resolver  HostResolver
	converter PriceConverter
}

func NewService(logger *slog.Logger, fast Scraper, headless Scraper, resolver HostResolver, converter PriceConverter) *Service {
	if resolver == nil {
		resolver = net.DefaultResolver
	}
	if converter == nil {
		converter = IdentityPriceConverter{}
	}

	return &Service{
		logger:    logger,
		fast:      fast,
		headless:  headless,
		resolver:  resolver,
		converter: converter,
	}
}

func (s *Service) Scrape(ctx context.Context, rawURL string, targetCurrencyCode string) (Product, error) {
	targetCurrency, err := NormalizeCurrencyCode(targetCurrencyCode)
	if err != nil {
		return Product{}, err
	}

	validatedURL, err := NormalizeProductURL(ctx, s.resolver, rawURL)
	if err != nil {
		return Product{}, err
	}

	startedAt := time.Now()

	fastResult, fastErr := s.fast.Scrape(ctx, validatedURL.String())
	if fastErr == nil {
		fastResult = fastResult.WithSource(sourceFast)
		if fastResult.IsComplete() {
			converted, convertErr := s.convertProductPrice(fastResult, targetCurrency)
			if convertErr == nil {
				fastResult = converted
				if converted.HasHighConfidencePrice() {
					s.logger.Info(
						"scrape completed",
						"url", validatedURL.String(),
						"source", sourceFast,
						"duration_ms", time.Since(startedAt).Milliseconds(),
					)
					return converted, nil
				}
			} else {
				fastErr = convertErr
			}
		}
	}

	headlessResult, headlessErr := s.headless.Scrape(ctx, validatedURL.String())
	if headlessErr == nil {
		headlessResult = headlessResult.WithSource(sourceHeadless)
		if headlessResult.IsComplete() {
			converted, convertErr := s.convertProductPrice(headlessResult, targetCurrency)
			if convertErr == nil {
				headlessResult = converted
				if converted.HasHighConfidencePrice() {
					s.logger.Info(
						"scrape completed",
						"url", validatedURL.String(),
						"source", sourceHeadless,
						"duration_ms", time.Since(startedAt).Milliseconds(),
					)
					return converted, nil
				}
			} else {
				headlessErr = convertErr
			}
		}
	}

	bestEffort := chooseBestProduct(fastResult, headlessResult)
	if bestEffort.IsComplete() {
		s.logger.Info(
			"scrape completed with price review metadata",
			"url", validatedURL.String(),
			"source", bestEffort.Source,
			"price_confidence", bestEffort.PriceConfidence,
			"duration_ms", time.Since(startedAt).Milliseconds(),
		)
		return bestEffort, nil
	}
	if bestEffort.HasAnyData() {
		s.logger.Warn(
			"scrape failed with partial data",
			"url", validatedURL.String(),
			"source", bestEffort.Source,
			"duration_ms", time.Since(startedAt).Milliseconds(),
			"fast_error", errorMessage(fastErr),
			"headless_error", errorMessage(headlessErr),
		)
		return bestEffort, ScrapeFailed("could not extract complete product details")
	}

	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return Product{}, Timeout("scrape timed out")
	}

	s.logger.Warn(
		"scrape failed",
		"url", validatedURL.String(),
		"duration_ms", time.Since(startedAt).Milliseconds(),
		"fast_error", errorMessage(fastErr),
		"headless_error", errorMessage(headlessErr),
	)

	return Product{}, ScrapeFailed("could not extract complete product details")
}

func (s *Service) convertProductPrice(product Product, targetCurrencyCode string) (Product, error) {
	amount, currency, err := s.converter.Convert(product.PriceAmount, product.PriceCurrency, targetCurrencyCode)
	if err != nil {
		return Product{}, err
	}
	product.PriceAmount = amount
	product.PriceCurrency = currency
	return product, nil
}

func errorMessage(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func chooseBestProduct(products ...Product) Product {
	best := Product{}
	bestScore := -1

	for _, product := range products {
		score := product.FilledFieldCount()*10 + priceConfidenceScore(product.PriceConfidence)
		if score > bestScore {
			best = product
			bestScore = score
			continue
		}
		if score == bestScore && product.Source == sourceHeadless && best.Source != sourceHeadless {
			best = product
		}
	}

	return best
}

func priceConfidenceScore(confidence string) int {
	switch confidence {
	case PriceConfidenceHigh:
		return 4
	case PriceConfidenceMedium:
		return 3
	case PriceConfidenceLow:
		return 2
	case PriceConfidenceSuspicious:
		return 1
	default:
		return 0
	}
}
