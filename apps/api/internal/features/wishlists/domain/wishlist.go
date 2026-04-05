package domain

import "time"

const (
	ItemPriorityLow    = "Low"
	ItemPriorityMedium = "Medium"
	ItemPriorityHigh   = "High"

	ItemStatusSaved       = "Saved"
	ItemStatusConsidering = "Considering"
	ItemStatusPurchased   = "Purchased"
)

type Wishlist struct {
	ID            string
	OwnerID       string
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
	CreatedAt     time.Time
	UpdatedAt     time.Time
	IsArchived    bool
	IsShared      bool
	SharedUsers   []SharedUser
	Items         []WishlistItem
}

type SharedUser struct {
	ID    string
	Name  string
	Email string
	Role  string
}

type WishlistItem struct {
	ID          string
	Title       string
	Rank        int
	Notes       *string
	PriceLabel  *string
	Priority    string
	Status      string
	ImageURL    *string
	ProductURL  *string
	PurchasedAt *time.Time
	CreatedAt   time.Time
	UpdatedAt   time.Time
}
