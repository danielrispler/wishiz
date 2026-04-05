package ports

import (
	"context"
	"errors"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
)

var ErrNotFound = errors.New("wishlists repository: not found")

type Repository interface {
	List(ctx context.Context, requestUserID string, requestUserEmail string) ([]domain.Wishlist, error)
	GetByID(ctx context.Context, id string) (domain.Wishlist, error)
	Create(ctx context.Context, params CreateWishlistParams) (domain.Wishlist, error)
	Update(ctx context.Context, params UpdateWishlistParams) (domain.Wishlist, error)
	Delete(ctx context.Context, id string) error
	Archive(ctx context.Context, id string) (domain.Wishlist, error)
	Restore(ctx context.Context, id string) (domain.Wishlist, error)
	AddItem(ctx context.Context, params AddItemParams) (domain.WishlistItem, error)
	UpdateItem(ctx context.Context, params UpdateItemParams) (domain.WishlistItem, error)
	DeleteItem(ctx context.Context, wishlistID string, itemID string) error
	ReorderItems(ctx context.Context, wishlistID string, orderedItemIDs []string) error
	AddSharedUser(ctx context.Context, wishlistID string, user domain.SharedUser) error
	RemoveSharedUser(ctx context.Context, wishlistID string, userID string) error
}

type CreateWishlistParams struct {
	OwnerID       string
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
	IsShared      bool
}

type UpdateWishlistParams struct {
	ID            string
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
	IsShared      bool
}

type AddItemParams struct {
	WishlistID  string
	Title       string
	Notes       *string
	PriceLabel  *string
	Priority    string
	Status      string
	ImageURL    *string
	ProductURL  *string
	PurchasedAt *time.Time
}

type UpdateItemParams struct {
	WishlistID  string
	ItemID      string
	Title       string
	Rank        int
	Notes       *string
	PriceLabel  *string
	Priority    string
	Status      string
	ImageURL    *string
	ProductURL  *string
	PurchasedAt *time.Time
}
