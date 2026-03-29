package ports

import (
	"context"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
)

type Repository interface {
	List(ctx context.Context) ([]domain.Wishlist, error)
	Create(ctx context.Context, title string, description string, year int) (domain.Wishlist, error)
}
