package postgres

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/ports"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) CreateOrGet(ctx context.Context, params ports.CreateJobParams, dedupeWindow time.Duration) (domain.Job, bool, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return domain.Job{}, false, fmt.Errorf("begin product import create transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	job, err := getByClientRequestID(ctx, tx, params.UserID, params.ClientRequestID)
	if err == nil {
		return job, true, tx.Commit(ctx)
	}
	if !errors.Is(err, ports.ErrNotFound) {
		return domain.Job{}, false, err
	}

	if params.WishlistID != nil {
		job, err = getRecentDuplicate(ctx, tx, params, time.Now().UTC().Add(-dedupeWindow))
		if err == nil {
			return job, true, tx.Commit(ctx)
		}
		if !errors.Is(err, ports.ErrNotFound) {
			return domain.Job{}, false, err
		}
	}

	row := tx.QueryRow(ctx, `
		INSERT INTO product_import_jobs (
			user_id,
			wishlist_id,
			client_request_id,
			normalized_url,
			domain,
			target_currency_code
		)
		VALUES ($1::uuid, NULLIF($2, '')::uuid, $3, $4, $5, $6)
		RETURNING `+jobColumns,
		params.UserID,
		ptrOrEmpty(params.WishlistID),
		params.ClientRequestID,
		params.NormalizedURL,
		params.Domain,
		params.TargetCurrencyCode,
	)
	job, err = scanJob(row)
	if isUniqueViolation(err) {
		existing, getErr := getByClientRequestID(ctx, tx, params.UserID, params.ClientRequestID)
		if getErr != nil {
			return domain.Job{}, false, getErr
		}
		return existing, true, tx.Commit(ctx)
	}
	if err != nil {
		return domain.Job{}, false, fmt.Errorf("insert product import job: %w", err)
	}
	return job, false, tx.Commit(ctx)
}

func (r *Repository) List(ctx context.Context, params ports.ListJobsParams) ([]domain.Job, error) {
	args := []any{params.UserID, params.Since, params.Limit, params.Offset}
	statusFilter := ""
	if len(params.Statuses) > 0 {
		placeholders := make([]string, 0, len(params.Statuses))
		for _, status := range params.Statuses {
			args = append(args, status)
			placeholders = append(placeholders, fmt.Sprintf("$%d", len(args)))
		}
		statusFilter = " AND status IN (" + strings.Join(placeholders, ", ") + ")"
	}

	rows, err := r.pool.Query(ctx, `
		SELECT `+jobColumns+`
		FROM product_import_jobs
		WHERE user_id = $1::uuid
			AND acknowledged_at IS NULL
			AND (
				status IN ('pending', 'processing')
				OR updated_at >= $2
			)
		`+statusFilter+`
		ORDER BY created_at DESC
		LIMIT $3 OFFSET $4
	`, args...)
	if err != nil {
		return nil, fmt.Errorf("list product import jobs: %w", err)
	}
	defer rows.Close()

	jobs := make([]domain.Job, 0)
	for rows.Next() {
		job, scanErr := scanJob(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		jobs = append(jobs, job)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate product import jobs: %w", err)
	}
	return jobs, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (domain.Job, error) {
	job, err := scanJob(r.pool.QueryRow(ctx, `SELECT `+jobColumns+` FROM product_import_jobs WHERE id = $1::uuid`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("get product import job %s: %w", id, err)
	}
	return job, nil
}

func (r *Repository) Retry(ctx context.Context, id string) (domain.Job, error) {
	job, err := scanJob(r.pool.QueryRow(ctx, `
		UPDATE product_import_jobs
		SET status = 'pending',
			last_error = NULL,
			error_code = NULL,
			retryable = FALSE,
			locked_at = NULL
		WHERE id = $1::uuid
			AND status IN ('failed', 'needs_review')
			AND retryable = TRUE
		RETURNING `+jobColumns,
		id,
	))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("retry product import job %s: %w", id, err)
	}
	return job, nil
}

func (r *Repository) Acknowledge(ctx context.Context, id string, acknowledgedAt time.Time) (domain.Job, error) {
	job, err := scanJob(r.pool.QueryRow(ctx, `
		UPDATE product_import_jobs
		SET acknowledged_at = $2
		WHERE id = $1::uuid
		RETURNING `+jobColumns,
		id,
		acknowledgedAt,
	))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("acknowledge product import job %s: %w", id, err)
	}
	return job, nil
}

func (r *Repository) ReleaseStuck(
	ctx context.Context, params ports.ReleaseStuckParams,
) (releasedCount int64, failedCount int64, err error) {
	released, err := r.pool.Exec(ctx, `
		UPDATE product_import_jobs
		SET status = 'pending',
			locked_at = NULL,
			retryable = TRUE,
			error_code = $3,
			last_error = $4
		WHERE status = 'processing'
			AND locked_at < $1
			AND attempt_count < $2
	`, params.LeaseExpiredBefore, params.MaxAttempts, params.TimeoutErrorCode, params.FailedMessage)
	if err != nil {
		return 0, 0, fmt.Errorf("release stuck product import jobs: %w", err)
	}

	failed, err := r.pool.Exec(ctx, `
		UPDATE product_import_jobs
		SET status = 'failed',
			locked_at = NULL,
			retryable = FALSE,
			error_code = $3,
			last_error = $4
		WHERE status = 'processing'
			AND locked_at < $1
			AND attempt_count >= $2
	`, params.LeaseExpiredBefore, params.MaxAttempts, params.TimeoutErrorCode, params.FailedMessage)
	if err != nil {
		return released.RowsAffected(), 0, fmt.Errorf("fail stuck product import jobs: %w", err)
	}
	return released.RowsAffected(), failed.RowsAffected(), nil
}

func (r *Repository) ClaimNext(ctx context.Context, params ports.ClaimParams) (domain.Job, error) {
	job, err := scanJob(r.pool.QueryRow(ctx, `
		UPDATE product_import_jobs
		SET status = 'processing',
			locked_at = $1,
			last_attempted_at = $1,
			attempt_count = attempt_count + 1,
			retryable = FALSE,
			progress_stage = 'validating',
			progress_percent = 0
		WHERE id = (
			SELECT id
			FROM product_import_jobs
			WHERE (
					status = 'pending'
					OR (
						status IN ('failed', 'needs_review')
						AND retryable = TRUE
						AND attempt_count < $2
						AND COALESCE(last_attempted_at, created_at) <= $1::timestamptz - make_interval(secs => 30 * (attempt_count + 1))
					)
				)
				AND attempt_count < $2
			ORDER BY created_at
			FOR UPDATE SKIP LOCKED
			LIMIT 1
		)
		RETURNING `+jobColumns,
		params.Now,
		params.MaxAttempts,
	))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("claim product import job: %w", err)
	}
	return job, nil
}

// UpdateProgress records the live scrape progress for a processing job. It is a
// single best-effort UPDATE guarded by status='processing' so a settled job is
// never resurrected by a late progress write.
func (r *Repository) UpdateProgress(ctx context.Context, id string, stage string, percent int) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE product_import_jobs
		SET progress_stage = $2, progress_percent = $3
		WHERE id = $1::uuid AND status = 'processing'`,
		id, stage, percent,
	)
	if err != nil {
		return fmt.Errorf("update product import progress: %w", err)
	}
	return nil
}

func (r *Repository) Settle(ctx context.Context, id string, outcome ports.JobOutcome) (domain.Job, error) {
	switch outcome.Status {
	case domain.StatusCompleted:
		return r.settleCompleted(ctx, id, outcome)
	case domain.StatusNeedsReview, domain.StatusFailed:
		return r.settleErrored(ctx, id, outcome)
	default:
		return domain.Job{}, fmt.Errorf("settle: unexpected status %q", outcome.Status)
	}
}

func (r *Repository) settleCompleted(ctx context.Context, id string, outcome ports.JobOutcome) (domain.Job, error) {
	return r.updateResult(ctx, `
		UPDATE product_import_jobs
		SET status = 'completed',
			title = $2,
			price_label = $3,
			price_confidence = $4,
			price_source = $5,
			price_warnings = COALESCE($6::text[], ARRAY[]::text[]),
			image_url = $7,
			completeness = $8,
			created_item_id = NULLIF($9, '')::uuid,
			last_error = NULL,
			error_code = NULL,
			retryable = FALSE,
			locked_at = NULL
		WHERE id = $1::uuid AND status = 'processing'
		RETURNING `+jobColumns,
		id,
		*outcome.Snapshot.Title,
		*outcome.Snapshot.PriceLabel,
		outcome.Snapshot.PriceConfidence,
		outcome.Snapshot.PriceSource,
		outcome.Snapshot.PriceWarnings,
		*outcome.Snapshot.ImageURL,
		outcome.Snapshot.Completeness,
		ptrOrEmpty(outcome.CreatedItemID),
	)
}

func (r *Repository) settleErrored(ctx context.Context, id string, outcome ports.JobOutcome) (domain.Job, error) {
	return r.updateResult(ctx, `
		UPDATE product_import_jobs
		SET status = $12,
			title = $2,
			price_label = $3,
			price_confidence = $4,
			price_source = $5,
			price_warnings = COALESCE($6::text[], ARRAY[]::text[]),
			image_url = $7,
			completeness = $8,
			last_error = $9,
			error_code = $10,
			retryable = $11,
			locked_at = NULL
		WHERE id = $1::uuid AND status = 'processing'
		RETURNING `+jobColumns,
		id,
		outcome.Snapshot.Title,
		outcome.Snapshot.PriceLabel,
		outcome.Snapshot.PriceConfidence,
		outcome.Snapshot.PriceSource,
		outcome.Snapshot.PriceWarnings,
		outcome.Snapshot.ImageURL,
		outcome.Snapshot.Completeness,
		outcome.LastError,
		outcome.ErrorCode,
		outcome.Retryable,
		outcome.Status,
	)
}

func (r *Repository) Assign(ctx context.Context, id string, wishlistID string, createdItemID string) (domain.Job, error) {
	return r.updateResult(ctx, `
		UPDATE product_import_jobs
		SET wishlist_id = $2::uuid,
			created_item_id = $3::uuid
		WHERE id = $1::uuid
		RETURNING `+jobColumns,
		id,
		wishlistID,
		createdItemID,
	)
}

func (r *Repository) updateResult(ctx context.Context, query string, args ...any) (domain.Job, error) {
	job, err := scanJob(r.pool.QueryRow(ctx, query, args...))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("update product import job result: %w", err)
	}
	return job, nil
}

func getByClientRequestID(ctx context.Context, q rowQueryer, userID string, clientRequestID string) (domain.Job, error) {
	job, err := scanJob(q.QueryRow(ctx, `
		SELECT `+jobColumns+`
		FROM product_import_jobs
		WHERE user_id = $1::uuid
			AND client_request_id = $2
	`, userID, clientRequestID))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("get product import job by client request id: %w", err)
	}
	return job, nil
}

func getRecentDuplicate(ctx context.Context, q rowQueryer, params ports.CreateJobParams, since time.Time) (domain.Job, error) {
	job, err := scanJob(q.QueryRow(ctx, `
		SELECT `+jobColumns+`
		FROM product_import_jobs
		WHERE user_id = $1::uuid
			AND wishlist_id = $2::uuid
			AND normalized_url = $3
			AND created_at >= $4
		ORDER BY created_at DESC
		LIMIT 1
	`, params.UserID, params.WishlistID, params.NormalizedURL, since))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Job{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Job{}, fmt.Errorf("get duplicate product import job: %w", err)
	}
	return job, nil
}

type rowQueryer interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

type scanner interface {
	Scan(...any) error
}

func scanJob(row scanner) (domain.Job, error) {
	var job domain.Job
	var wishlistID sql.NullString
	var lastAttemptedAt sql.NullTime
	var lastError sql.NullString
	var errorCode sql.NullString
	var title sql.NullString
	var priceLabel sql.NullString
	var priceConfidence sql.NullString
	var priceSource sql.NullString
	var imageURL sql.NullString
	var createdItemID sql.NullString
	var acknowledgedAt sql.NullTime
	var lockedAt sql.NullTime

	err := row.Scan(
		&job.ID,
		&job.UserID,
		&wishlistID,
		&job.ClientRequestID,
		&job.NormalizedURL,
		&job.Domain,
		&job.TargetCurrencyCode,
		&job.Status,
		&job.AttemptCount,
		&lastAttemptedAt,
		&lastError,
		&errorCode,
		&job.Retryable,
		&title,
		&priceLabel,
		&priceConfidence,
		&priceSource,
		&job.PriceWarnings,
		&imageURL,
		&job.Completeness,
		&createdItemID,
		&acknowledgedAt,
		&lockedAt,
		&job.CreatedAt,
		&job.UpdatedAt,
		&job.ProgressStage,
		&job.ProgressPercent,
	)
	if err != nil {
		return domain.Job{}, err
	}

	job.WishlistID = nullableString(wishlistID)
	job.LastAttemptedAt = nullableTime(lastAttemptedAt)
	job.LastError = nullableString(lastError)
	job.ErrorCode = nullableString(errorCode)
	job.Title = nullableString(title)
	job.PriceLabel = nullableString(priceLabel)
	job.PriceConfidence = nullableString(priceConfidence)
	job.PriceSource = nullableString(priceSource)
	job.ImageURL = nullableString(imageURL)
	job.CreatedItemID = nullableString(createdItemID)
	job.AcknowledgedAt = nullableTime(acknowledgedAt)
	job.LockedAt = nullableTime(lockedAt)
	return job, nil
}

func nullableString(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}
	return &value.String
}

func nullableTime(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	return &value.Time
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

func ptrOrEmpty(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

const jobColumns = `
	id::text,
	user_id::text,
	wishlist_id::text,
	client_request_id,
	normalized_url,
	domain,
	target_currency_code,
	status,
	attempt_count,
	last_attempted_at,
	last_error,
	error_code,
	retryable,
	title,
	price_label,
	price_confidence,
	price_source,
	COALESCE(price_warnings, ARRAY[]::text[]),
	image_url,
	completeness,
	created_item_id::text,
	acknowledged_at,
	locked_at,
	created_at,
	updated_at,
	COALESCE(progress_stage, ''),
	progress_percent`
