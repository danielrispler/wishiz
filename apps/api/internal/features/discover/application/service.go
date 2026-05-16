package application

import (
	"context"
	"errors"
	"strings"

	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/ports"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

type DiscoverFeed struct {
	StarterPacks []domain.StarterPack
	Trending     []domain.DiscoverProduct
	ForYou       []domain.DiscoverProduct
}

type Service struct {
	repo         ports.Repository
	scrapeService *scrapeapp.Service
}

func NewService(repo ports.Repository, scrapeService *scrapeapp.Service) *Service {
	return &Service{repo: repo, scrapeService: scrapeService}
}

func (s *Service) GetFeed(ctx context.Context, userID string, categories, brands []string) (DiscoverFeed, error) {
	trending, err := s.repo.GetTrending(ctx, userID, 10)
	if err != nil {
		return DiscoverFeed{}, err
	}

	forYou, err := s.repo.GetForYou(ctx, userID, categories, brands, 20)
	if err != nil {
		return DiscoverFeed{}, err
	}

	packs, err := s.repo.GetStarterPacks(ctx, userID)
	if err != nil {
		return DiscoverFeed{}, err
	}

	return DiscoverFeed{
		StarterPacks: packs,
		Trending:     trending,
		ForYou:       forYou,
	}, nil
}

func (s *Service) ToggleSave(ctx context.Context, userID, productID string) (bool, int, error) {
	if strings.TrimSpace(userID) == "" {
		return false, 0, ValidationError("userID", "userID is required")
	}
	if strings.TrimSpace(productID) == "" {
		return false, 0, ValidationError("productID", "productID is required")
	}
	saved, count, err := s.repo.ToggleSave(ctx, userID, productID)
	if errors.Is(err, ports.ErrNotFound) {
		return false, 0, NotFound("product not found")
	}
	return saved, count, err
}

func (s *Service) GrabStarterPack(ctx context.Context, userID, packID, wishlistID string) (int, error) {
	if strings.TrimSpace(userID) == "" {
		return 0, ValidationError("userID", "userID is required")
	}
	if strings.TrimSpace(packID) == "" {
		return 0, ValidationError("packID", "packID is required")
	}
	if strings.TrimSpace(wishlistID) == "" {
		return 0, ValidationError("wishlistID", "wishlistID is required")
	}
	n, err := s.repo.GrabStarterPack(ctx, userID, packID, wishlistID)
	if errors.Is(err, ports.ErrNotFound) {
		return 0, NotFound("starter pack or wishlist not found")
	}
	return n, err
}

func (s *Service) SeedProduct(ctx context.Context, rawURL, category string) (domain.DiscoverProduct, error) {
	category = strings.ToLower(strings.TrimSpace(category))
	if category == "" {
		return domain.DiscoverProduct{}, ValidationError("category", "category is required")
	}

	scraped, err := s.scrapeService.Scrape(ctx, rawURL, "USD")
	if err != nil {
		return domain.DiscoverProduct{}, err
	}

	if scraped.Name == "" || scraped.ImageURL == "" {
		return domain.DiscoverProduct{}, ValidationError("url", "could not extract product name or image from URL")
	}

	var priceLabel *string
	if scraped.PriceAmount != "" {
		pl := scraped.PriceAmount
		if scraped.PriceCurrency != "" {
			pl = scraped.PriceCurrency + " " + pl
		}
		priceLabel = &pl
	}

	var productURL *string
	if rawURL != "" {
		u := rawURL
		productURL = &u
	}

	return s.repo.SeedProduct(ctx, ports.SeedProductInput{
		Title:      scraped.Name,
		Brand:      extractBrand(rawURL),
		Category:   category,
		ImageURL:   scraped.ImageURL,
		PriceLabel: priceLabel,
		ProductURL: productURL,
	})
}

func (s *Service) CreateStarterPack(ctx context.Context, title, subtitle, coverImageURL string, productIDs []string) (domain.StarterPack, error) {
	if strings.TrimSpace(title) == "" {
		return domain.StarterPack{}, ValidationError("title", "title is required")
	}
	if strings.TrimSpace(coverImageURL) == "" {
		return domain.StarterPack{}, ValidationError("coverImageURL", "coverImageURL is required")
	}
	return s.repo.CreateStarterPack(ctx, strings.TrimSpace(title), strings.TrimSpace(subtitle), coverImageURL, productIDs)
}

func extractBrand(rawURL string) string {
	rawURL = strings.TrimPrefix(rawURL, "https://")
	rawURL = strings.TrimPrefix(rawURL, "http://")
	rawURL = strings.TrimPrefix(rawURL, "www.")
	if idx := strings.Index(rawURL, "/"); idx > 0 {
		rawURL = rawURL[:idx]
	}
	parts := strings.Split(rawURL, ".")
	if len(parts) > 0 {
		brand := parts[0]
		brand = strings.Title(strings.ToLower(brand))
		return brand
	}
	return rawURL
}
