package domain

import "time"

const (
	StatusPending     = "pending"
	StatusProcessing  = "processing"
	StatusCompleted   = "completed"
	StatusNeedsReview = "needs_review"
	StatusFailed      = "failed"
)

type Job struct {
	ID                 string
	UserID             string
	WishlistID         *string
	ClientRequestID    string
	NormalizedURL      string
	Domain             string
	TargetCurrencyCode string
	Status             string
	AttemptCount       int
	LastAttemptedAt    *time.Time
	LastError          *string
	ErrorCode          *string
	Retryable          bool
	Title              *string
	PriceLabel         *string
	PriceAmount        *string
	PriceAmountMax     *string
	PriceCurrencyCode  *string
	PriceConfidence    *string
	PriceSource        *string
	PriceWarnings      []string
	ImageURL           *string
	Completeness       int
	ProgressStage      string
	ProgressPercent    int
	CreatedItemID      *string
	AcknowledgedAt     *time.Time
	LockedAt           *time.Time
	CreatedAt          time.Time
	UpdatedAt          time.Time
}

func IsTerminalStatus(status string) bool {
	return status == StatusCompleted || status == StatusNeedsReview || status == StatusFailed
}
