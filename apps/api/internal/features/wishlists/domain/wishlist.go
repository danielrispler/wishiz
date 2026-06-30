package domain

import "time"

const (
	ItemPriorityLow    = "low"
	ItemPriorityMedium = "medium"
	ItemPriorityHigh   = "high"

	ItemStatusSaved       = "saved"
	ItemStatusConsidering = "considering"
	ItemStatusPurchased   = "purchased"

	MemberRoleViewer = "viewer"
	MemberRoleEditor = "editor"
)

type Wishlist struct {
	ID            string
	OwnerID       string
	OwnerFullName string
	Title         string
	Description   string
	Year          int
	CoverImageURL *string
	ShareToken    string
	CreatedAt     time.Time
	UpdatedAt     time.Time
	IsArchived    bool
	Members       []WishlistMember
	Invites       []WishlistInvite
	Items         []WishlistItem
}

type WishlistMember struct {
	WishlistID string
	UserID     string
	Email      string
	FullName   string
	Role       string
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

type WishlistInvite struct {
	ID              string
	WishlistID      string
	Email           *string
	Role            string
	InvitedByUserID *string
	AcceptedAt      *time.Time
	ExpiresAt       time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
	Token           string
}

type WishlistItem struct {
	ID                string
	Title             string
	Rank              int
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
	CreatedAt         time.Time
	UpdatedAt         time.Time
}
