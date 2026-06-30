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
	// ClaimByID atomically claims one specific pending job (the Cloud Tasks
	// directed-dispatch path). It returns ErrNotFound when the job is absent or
	// no longer pending (already claimed, terminal, or redelivered) so the caller
	// can treat that as an idempotent no-op.
	ClaimByID(ctx context.Context, id string, now time.Time) (domain.Job, error)
	// ReleaseToPending reverts a still-processing job back to pending (best-effort,
	// no-op on terminal rows) so a Cloud Tasks retry re-claims it promptly when the
	// final Settle write failed, instead of waiting for the lease-timeout sweep.
	ReleaseToPending(ctx context.Context, id string) error
	UpdateProgress(ctx context.Context, id string, stage string, percent int) error
	Settle(ctx context.Context, id string, outcome JobOutcome) (domain.Job, error)
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

type ProductSnapshot struct {
	Title             *string
	PriceLabel        *string
	PriceAmount       *string
	PriceAmountMax    *string
	PriceCurrencyCode *string
	PriceConfidence   *string
	PriceSource       *string
	PriceWarnings     []string
	ImageURL          *string
	Completeness      int
}

type JobOutcome struct {
	Status        string
	Snapshot      ProductSnapshot
	LastError     string
	ErrorCode     string
	Retryable     bool
	CreatedItemID *string
}
