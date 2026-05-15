package ports

import (
	"context"
	"errors"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
)

var ErrNotFound = errors.New("product imports repository: not found")

type Repository interface {
	CreateOrGet(ctx context.Context, params CreateJobParams, dedupeWindow time.Duration) (domain.Job, bool, error)
	List(ctx context.Context, params ListJobsParams) ([]domain.Job, error)
	GetByID(ctx context.Context, id string) (domain.Job, error)
	Retry(ctx context.Context, id string) (domain.Job, error)
	Acknowledge(ctx context.Context, id string, acknowledgedAt time.Time) (domain.Job, error)
	ReleaseStuck(ctx context.Context, params ReleaseStuckParams) (int64, int64, error)
	ClaimNext(ctx context.Context, params ClaimParams) (domain.Job, error)
	MarkCompleted(ctx context.Context, params CompleteJobParams) (domain.Job, error)
	MarkNeedsReview(ctx context.Context, params NeedsReviewJobParams) (domain.Job, error)
	MarkFailed(ctx context.Context, params FailJobParams) (domain.Job, error)
	Assign(ctx context.Context, id string, wishlistID string, createdItemID string) (domain.Job, error)
}

type CreateJobParams struct {
	UserID             string
	WishlistID         *string
	ClientRequestID    string
	NormalizedURL      string
	Domain             string
	TargetCurrencyCode string
}

type ListJobsParams struct {
	UserID   string
	Statuses []string
	Limit    int
	Offset   int
	Since    time.Time
}

type ReleaseStuckParams struct {
	LeaseExpiredBefore time.Time
	MaxAttempts        int
	RetryableErrorCode string
	TimeoutErrorCode   string
	FailedMessage      string
}

type ClaimParams struct {
	Now         time.Time
	MaxAttempts int
	Limit       int
}

type CompleteJobParams struct {
	ID              string
	Title           string
	PriceLabel      string
	PriceConfidence *string
	PriceSource     *string
	PriceWarnings   []string
	ImageURL        string
	Completeness    int
	CreatedItemID   *string
}

type NeedsReviewJobParams struct {
	ID              string
	Title           *string
	PriceLabel      *string
	PriceConfidence *string
	PriceSource     *string
	PriceWarnings   []string
	ImageURL        *string
	Completeness    int
	LastError       string
	ErrorCode       string
	Retryable       bool
}

type FailJobParams struct {
	ID              string
	Title           *string
	PriceLabel      *string
	PriceConfidence *string
	PriceSource     *string
	PriceWarnings   []string
	ImageURL        *string
	Completeness    int
	LastError       string
	ErrorCode       string
	Retryable       bool
}
