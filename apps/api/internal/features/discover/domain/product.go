package domain

import "time"

type DiscoverProduct struct {
	ID               string
	Title            string
	Brand            string
	Category         string
	ImageURL         string
	ProductURL       *string
	SaveCount        int
	SavedByUser      bool
	CreatedAt        time.Time
	PriceLabel       *string
	Gender           *string
	ProductType      *string
	SavedItemID      *string
	SavedWishlistID  *string
}

type StarterPack struct {
	ID            string
	Title         string
	Subtitle      string
	CoverImageURL string
	ItemCount     int
	PreviewItems  []string
	Items         []DiscoverProduct
}
