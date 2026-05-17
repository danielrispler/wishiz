package ports

import (
	"context"
	"errors"

	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/domain"
)

var ErrNotFound = errors.New("discover repository: not found")

type SeedProductInput struct {
	Title       string
	Brand       string
	Category    string
	ImageURL    string
	ProductURL  *string
	PriceLabel  *string
	Gender      *string
	ProductType *string
}

type Repository interface {
	GetTrending(ctx context.Context, userID string, limit int) ([]domain.DiscoverProduct, error)
	GetForYou(ctx context.Context, userID string, brands []string, gender *string, limit int) ([]domain.DiscoverProduct, error)
	GetStarterPacks(ctx context.Context, userID string) ([]domain.StarterPack, error)
	ToggleSave(ctx context.Context, userID, productID string) (saved bool, newCount int, err error)
	GrabStarterPack(ctx context.Context, userID, packID, wishlistID string) (itemsAdded int, err error)
	SeedProduct(ctx context.Context, in SeedProductInput) (domain.DiscoverProduct, error)
	CreateStarterPack(ctx context.Context, title, subtitle, coverImageURL string, productIDs []string) (domain.StarterPack, error)
}
