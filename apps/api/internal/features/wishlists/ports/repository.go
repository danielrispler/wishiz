package ports

import (
	"context"
	"errors"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
)

var ErrNotFound = errors.New("wishlists repository: not found")

type Repository interface {
	List(ctx context.Context, requestUserID string) ([]domain.Wishlist, error)
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
	CreateInvite(ctx context.Context, params CreateInviteParams) (domain.WishlistInvite, error)
	DeleteInvite(ctx context.Context, wishlistID string, inviteID string) error
	GetInviteByTokenHash(ctx context.Context, wishlistID string, tokenHash string) (domain.WishlistInvite, error)
	AcceptInvite(ctx context.Context, params AcceptInviteParams) error
	AddMember(ctx context.Context, wishlistID string, userID string, role string) error
	RemoveMember(ctx context.Context, wishlistID string, userID string) error
	UpdateMemberRole(ctx context.Context, wishlistID string, userID string, role string) error
}

type CreateWishlistParams struct {
	OwnerID       string
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
}

type UpdateWishlistParams struct {
	ID            string
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
}

type AddItemParams struct {
	WishlistID        string
	Title             string
	Notes             *string
	PriceLabel        *string
	PriceAmount       *string
	PriceAmountMax    *string
	PriceCurrencyCode *string
	Priority          string
	Status            string
	ImageURL          *string
	ProductURL        *string
	PurchasedAt       *time.Time
}

// UpdateItemParams carries the structured price amounts because editing the price
// label of a range item collapses it to a fixed price: PatchItem clears
// PriceAmount/PriceAmountMax (a human-entered label is no longer the import-time
// range snapshot). PriceCurrencyCode is left frozen (UpdateItem never touches that
// column). When the price label is NOT edited, these mirror the current row so the
// UPDATE preserves the import snapshot. See ADR-0007.
type UpdateItemParams struct {
	WishlistID     string
	ItemID         string
	Title          string
	Rank           int
	Notes          *string
	PriceLabel     *string
	PriceAmount    *string
	PriceAmountMax *string
	Priority       string
	Status         string
	ImageURL       *string
	ProductURL     *string
	PurchasedAt    *time.Time
}

type CreateInviteParams struct {
	WishlistID      string
	Email           *string
	Role            string
	InvitedByUserID string
	TokenHash       string
	ExpiresAt       time.Time
}

type AcceptInviteParams struct {
	InviteID   string
	WishlistID string
	UserID     string
	Role       string
	AcceptedAt time.Time
}
