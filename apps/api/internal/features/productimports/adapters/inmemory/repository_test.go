package inmemory

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/ports"
)

const maxAttempts = 3

func claim(t *testing.T, r *Repository, now time.Time) (domain.Job, error) {
	t.Helper()
	return r.ClaimNext(context.Background(), ports.ClaimParams{Now: now, MaxAttempts: maxAttempts, Limit: 1})
}

// The worker must auto-claim pending jobs only. needs_review and failed are
// user-gated terminal states: they re-enter the queue solely via explicit Retry,
// never on their own. This is the bug fix — the worker used to silently re-scrape
// "waiting to approve" (needs_review) items.
func TestClaimNextSkipsUserGatedStatuses(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	// Created long ago and last attempted long ago — well past any old backoff.
	old := now.Add(-1 * time.Hour)

	cases := []struct {
		name   string
		status string
	}{
		{"needs_review retryable is not auto-claimed", domain.StatusNeedsReview},
		{"failed retryable is not auto-claimed", domain.StatusFailed},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			r := NewRepository()
			r.Seed(domain.Job{
				Status:          tc.status,
				Retryable:       true,
				AttemptCount:    1,
				CreatedAt:       old,
				LastAttemptedAt: &old,
			})

			_, err := claim(t, r, now)
			if !errors.Is(err, ports.ErrNotFound) {
				t.Fatalf("expected %s job to be skipped (ErrNotFound), got err=%v", tc.status, err)
			}
		})
	}
}

func TestClaimNextClaimsPending(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r := NewRepository()
	r.Seed(domain.Job{Status: domain.StatusPending, CreatedAt: now.Add(-time.Minute)})

	job, err := claim(t, r, now)
	if err != nil {
		t.Fatalf("claim pending: %v", err)
	}
	if job.Status != domain.StatusProcessing {
		t.Fatalf("expected processing, got %q", job.Status)
	}
	if job.AttemptCount != 1 || job.Retryable {
		t.Fatalf("expected attempt=1 retryable=false, got attempt=%d retryable=%v", job.AttemptCount, job.Retryable)
	}
}

func TestClaimNextSkipsPendingAtMaxAttempts(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r := NewRepository()
	r.Seed(domain.Job{Status: domain.StatusPending, AttemptCount: maxAttempts, CreatedAt: now.Add(-time.Minute)})

	if _, err := claim(t, r, now); !errors.Is(err, ports.ErrNotFound) {
		t.Fatalf("expected pending job at max attempts to be skipped, got %v", err)
	}
}

// ClaimByID is the Cloud Tasks directed-dispatch path. It must claim a specific
// pending job and reject anything else (terminal, already-claimed, redelivered)
// with ErrNotFound so the dispatcher treats redelivery as an idempotent no-op.
func TestClaimByIDClaimsPendingThenIsIdempotent(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r := NewRepository()
	seeded := r.Seed(domain.Job{Status: domain.StatusPending, CreatedAt: now.Add(-time.Minute)})

	job, err := r.ClaimByID(context.Background(), seeded.ID, now)
	if err != nil {
		t.Fatalf("claim by id: %v", err)
	}
	if job.ID != seeded.ID || job.Status != domain.StatusProcessing || job.AttemptCount != 1 {
		t.Fatalf("expected claimed processing attempt=1, got id=%q status=%q attempt=%d", job.ID, job.Status, job.AttemptCount)
	}

	// Second delivery: the job is now processing, not pending -> no-op.
	if _, err := r.ClaimByID(context.Background(), seeded.ID, now); !errors.Is(err, ports.ErrNotFound) {
		t.Fatalf("expected ErrNotFound on redelivery of claimed job, got %v", err)
	}
}

func TestClaimByIDRejectsTerminalJob(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r := NewRepository()
	seeded := r.Seed(domain.Job{Status: domain.StatusNeedsReview, CreatedAt: now.Add(-time.Minute)})

	if _, err := r.ClaimByID(context.Background(), seeded.ID, now); !errors.Is(err, ports.ErrNotFound) {
		t.Fatalf("expected terminal job to be rejected, got %v", err)
	}
}

func TestRetryRequeuesNeedsReviewForClaiming(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	r := NewRepository()
	seeded := r.Seed(domain.Job{
		Status:       domain.StatusNeedsReview,
		Retryable:    true,
		AttemptCount: 1,
		CreatedAt:    now.Add(-time.Hour),
	})

	if _, err := r.Retry(context.Background(), seeded.ID); err != nil {
		t.Fatalf("retry: %v", err)
	}

	job, err := claim(t, r, now)
	if err != nil {
		t.Fatalf("claim after retry: %v", err)
	}
	if job.ID != seeded.ID || job.Status != domain.StatusProcessing {
		t.Fatalf("expected retried job to be claimed and processing, got id=%q status=%q", job.ID, job.Status)
	}
	if job.AttemptCount != 2 {
		t.Fatalf("expected attempt=2 after retry+claim, got %d", job.AttemptCount)
	}
}

func TestReleaseStuckRequeuesProcessingForClaiming(t *testing.T) {
	t.Parallel()

	now := time.Date(2026, 6, 20, 12, 0, 0, 0, time.UTC)
	leaseExpiry := now.Add(-2 * time.Minute)
	lockedLongAgo := now.Add(-5 * time.Minute)

	r := NewRepository()
	seeded := r.Seed(domain.Job{
		Status:       domain.StatusProcessing,
		AttemptCount: 1,
		LockedAt:     &lockedLongAgo,
		CreatedAt:    now.Add(-time.Hour),
	})

	released, failed, err := r.ReleaseStuck(context.Background(), ports.ReleaseStuckParams{
		LeaseExpiredBefore: leaseExpiry,
		MaxAttempts:        maxAttempts,
		TimeoutErrorCode:   "timeout",
		FailedMessage:      "stuck",
	})
	if err != nil {
		t.Fatalf("release stuck: %v", err)
	}
	if released != 1 || failed != 0 {
		t.Fatalf("expected released=1 failed=0, got released=%d failed=%d", released, failed)
	}

	job, err := claim(t, r, now)
	if err != nil {
		t.Fatalf("claim after release: %v", err)
	}
	if job.ID != seeded.ID || job.Status != domain.StatusProcessing {
		t.Fatalf("expected recovered job to be claimed, got id=%q status=%q", job.ID, job.Status)
	}
}
