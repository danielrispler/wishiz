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
	logger   *slog.Logger
	fast     Scraper
	headless Scraper
	resolver HostResolver
}

func NewService(logger *slog.Logger, fast Scraper, headless Scraper, resolver HostResolver) *Service {
	if resolver == nil {
		resolver = net.DefaultResolver
	}

	return &Service{
		logger:   logger,
		fast:     fast,
		headless: headless,
		resolver: resolver,
	}
}

func (s *Service) Scrape(ctx context.Context, rawURL string) (Product, error) {
	validatedURL, err := ValidateProductURL(ctx, s.resolver, rawURL)
	if err != nil {
		return Product{}, err
	}

	startedAt := time.Now()

	fastResult, fastErr := s.fast.Scrape(ctx, validatedURL.String())
	if fastErr == nil {
		fastResult = fastResult.WithSource(sourceFast)
		if fastResult.IsComplete() {
			s.logger.Info(
				"scrape completed",
				"url", validatedURL.String(),
				"source", sourceFast,
				"duration_ms", time.Since(startedAt).Milliseconds(),
			)
			return fastResult, nil
		}
	}

	headlessResult, headlessErr := s.headless.Scrape(ctx, validatedURL.String())
	if headlessErr == nil {
		headlessResult = headlessResult.WithSource(sourceHeadless)
		if headlessResult.IsComplete() {
			s.logger.Info(
				"scrape completed",
				"url", validatedURL.String(),
				"source", sourceHeadless,
				"duration_ms", time.Since(startedAt).Milliseconds(),
			)
			return headlessResult, nil
		}
	}

	bestEffort := chooseBestProduct(fastResult, headlessResult)
	if bestEffort.HasAnyData() {
		s.logger.Warn(
			"scrape completed with partial data",
			"url", validatedURL.String(),
			"source", bestEffort.Source,
			"duration_ms", time.Since(startedAt).Milliseconds(),
			"fast_error", errorMessage(fastErr),
			"headless_error", errorMessage(headlessErr),
		)
		return bestEffort, nil
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
		score := product.FilledFieldCount()
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
