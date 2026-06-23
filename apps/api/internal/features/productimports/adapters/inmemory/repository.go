// Package inmemory is a test-support adapter implementing ports.Repository.
// It mirrors the postgres adapter's claim/retry/recovery semantics closely
// enough to guard the worker contract (e.g. which statuses ClaimNext picks up)
// without a real database. Production wiring uses the postgres adapter.
package inmemory

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/ports"
)

type Repository struct {
	mu   sync.Mutex
	jobs map[string]*domain.Job
	seq  int
}

func NewRepository() *Repository {
	return &Repository{jobs: make(map[string]*domain.Job)}
}

// Seed inserts a job verbatim (any status) for test setup and returns a copy.
func (r *Repository) Seed(job domain.Job) domain.Job {
	r.mu.Lock()
	defer r.mu.Unlock()
	if job.ID == "" {
		r.seq++
		job.ID = fmt.Sprintf("job-%d", r.seq)
	}
	stored := job
	r.jobs[job.ID] = &stored
	return stored
}

func (r *Repository) CreateOrGet(
	_ context.Context, params ports.CreateJobParams, _ time.Duration,
) (domain.Job, bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, j := range r.jobs {
		if j.UserID == params.UserID && j.ClientRequestID == params.ClientRequestID {
			return *j, true, nil
		}
	}
	r.seq++
	job := domain.Job{
		ID:                 fmt.Sprintf("job-%d", r.seq),
		UserID:             params.UserID,
		WishlistID:         params.WishlistID,
		ClientRequestID:    params.ClientRequestID,
		NormalizedURL:      params.NormalizedURL,
		Domain:             params.Domain,
		TargetCurrencyCode: params.TargetCurrencyCode,
		Status:             domain.StatusPending,
	}
	stored := job
	r.jobs[job.ID] = &stored
	return stored, false, nil
}

func (r *Repository) List(_ context.Context, params ports.ListJobsParams) ([]domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]domain.Job, 0)
	for _, j := range r.jobs {
		if j.UserID != params.UserID || j.AcknowledgedAt != nil {
			continue
		}
		out = append(out, *j)
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	return out, nil
}

func (r *Repository) GetByID(_ context.Context, id string) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if j, ok := r.jobs[id]; ok {
		return *j, nil
	}
	return domain.Job{}, ports.ErrNotFound
}

func (r *Repository) Retry(_ context.Context, id string) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	j, ok := r.jobs[id]
	eligible := ok && j.Retryable && (j.Status == domain.StatusFailed || j.Status == domain.StatusNeedsReview)
	if !eligible {
		return domain.Job{}, ports.ErrNotFound
	}
	j.Status = domain.StatusPending
	j.LastError = nil
	j.ErrorCode = nil
	j.Retryable = false
	j.LockedAt = nil
	return *j, nil
}

func (r *Repository) Acknowledge(_ context.Context, id string, acknowledgedAt time.Time) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	j, ok := r.jobs[id]
	if !ok {
		return domain.Job{}, ports.ErrNotFound
	}
	j.AcknowledgedAt = &acknowledgedAt
	return *j, nil
}

func (r *Repository) ReleaseStuck(
	_ context.Context, params ports.ReleaseStuckParams,
) (releasedCount int64, failedCount int64, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, j := range r.jobs {
		if j.Status != domain.StatusProcessing || j.LockedAt == nil || !j.LockedAt.Before(params.LeaseExpiredBefore) {
			continue
		}
		if j.AttemptCount < params.MaxAttempts {
			j.Status = domain.StatusPending
			j.LockedAt = nil
			j.Retryable = true
			j.ErrorCode = ptrStr(params.TimeoutErrorCode)
			j.LastError = ptrStr(params.FailedMessage)
			releasedCount++
			continue
		}
		j.Status = domain.StatusFailed
		j.LockedAt = nil
		j.Retryable = false
		j.ErrorCode = ptrStr(params.TimeoutErrorCode)
		j.LastError = ptrStr(params.FailedMessage)
		failedCount++
	}
	return releasedCount, failedCount, nil
}

func (r *Repository) ClaimNext(_ context.Context, params ports.ClaimParams) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	candidates := make([]*domain.Job, 0)
	for _, j := range r.jobs {
		if r.claimable(j, params) {
			candidates = append(candidates, j)
		}
	}
	if len(candidates) == 0 {
		return domain.Job{}, ports.ErrNotFound
	}
	sort.Slice(candidates, func(i, k int) bool {
		return candidates[i].CreatedAt.Before(candidates[k].CreatedAt)
	})
	j := candidates[0]
	j.Status = domain.StatusProcessing
	j.LockedAt = ptrTime(params.Now)
	j.LastAttemptedAt = ptrTime(params.Now)
	j.AttemptCount++
	j.Retryable = false
	j.ProgressStage = "validating"
	j.ProgressPercent = 0
	return *j, nil
}

// claimable mirrors the postgres ClaimNext predicate: the worker auto-claims
// pending jobs only. needs_review and failed are user-gated terminal states and
// re-enter the queue solely via explicit Retry (which moves them to pending).
func (r *Repository) claimable(j *domain.Job, p ports.ClaimParams) bool {
	return j.Status == domain.StatusPending && j.AttemptCount < p.MaxAttempts
}

// ClaimByID claims one specific job only if it is still pending, mirroring the
// postgres adapter. A missing or non-pending job yields ErrNotFound so the
// directed-dispatch caller (Cloud Tasks) can treat redelivery as a no-op.
func (r *Repository) ClaimByID(_ context.Context, id string, now time.Time) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	j, ok := r.jobs[id]
	if !ok || j.Status != domain.StatusPending {
		return domain.Job{}, ports.ErrNotFound
	}
	j.Status = domain.StatusProcessing
	j.LockedAt = ptrTime(now)
	j.LastAttemptedAt = ptrTime(now)
	j.AttemptCount++
	j.Retryable = false
	j.ProgressStage = "validating"
	j.ProgressPercent = 0
	return *j, nil
}

func (r *Repository) ReleaseToPending(_ context.Context, id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if j, ok := r.jobs[id]; ok && j.Status == domain.StatusProcessing {
		j.Status = domain.StatusPending
		j.LockedAt = nil
		j.Retryable = true
	}
	return nil
}

func (r *Repository) UpdateProgress(_ context.Context, id string, stage string, percent int) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if j, ok := r.jobs[id]; ok && j.Status == domain.StatusProcessing {
		j.ProgressStage = stage
		j.ProgressPercent = percent
	}
	return nil
}

func (r *Repository) Settle(_ context.Context, id string, outcome ports.JobOutcome) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	j, ok := r.jobs[id]
	if !ok || j.Status != domain.StatusProcessing {
		return domain.Job{}, ports.ErrNotFound
	}
	j.Status = outcome.Status
	j.LockedAt = nil
	j.Retryable = outcome.Status != domain.StatusCompleted && outcome.Retryable
	j.LastError = nilIfEmpty(outcome.LastError)
	j.ErrorCode = nilIfEmpty(outcome.ErrorCode)
	j.CreatedItemID = outcome.CreatedItemID
	return *j, nil
}

func (r *Repository) Assign(_ context.Context, id string, wishlistID string, createdItemID string) (domain.Job, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	j, ok := r.jobs[id]
	if !ok {
		return domain.Job{}, ports.ErrNotFound
	}
	j.WishlistID = &wishlistID
	j.CreatedItemID = &createdItemID
	return *j, nil
}

func ptrTime(t time.Time) *time.Time { return &t }

func ptrStr(s string) *string { return &s }

func nilIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
