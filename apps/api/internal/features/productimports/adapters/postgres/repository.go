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
	if err != nil && !errors.Is(err, ports.ErrNotFound) {
		return domain.Job{}, false, err
	}

	job, err = getRecentDuplicate(ctx, tx, params, time.Now().UTC().Add(-dedupeWindow))
	if err == nil {
		return job, true, tx.Commit(ctx)
	}
	if err != nil && !errors.Is(err, ports.ErrNotFound) {
		return domain.Job{}, false, err
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
		VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6)
		RETURNING `+jobColumns,
		params.UserID,
		params.WishlistID,
		params.ClientRequestID,
		params.NormalizedURL,
		params.Domain,
		params.TargetCurrencyCode,
	)
	job, err = scanJob(row)
	if isUniqueViolation(err) {
		job, getErr := getByClientRequestID(ctx, tx, params.UserID, params.ClientRequestID)
		if getErr != nil {
			return domain.Job{}, false, getErr
		}
		return job, true, tx.Commit(ctx)
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

func (r *Repository) ReleaseStuck(ctx context.Context, params ports.ReleaseStuckParams) (int64, int64, error) {
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
			retryable = FALSE
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

func (r *Repository) MarkCompleted(ctx context.Context, params ports.CompleteJobParams) (domain.Job, error) {
	return r.updateResult(ctx, `
		UPDATE product_import_jobs
		SET status = 'completed',
			title = $2,
			price_label = $3,
			image_url = $4,
			completeness = $5,
			created_item_id = $6::uuid,
			last_error = NULL,
			error_code = NULL,
			retryable = FALSE,
			locked_at = NULL
		WHERE id = $1::uuid AND status = 'processing'
		RETURNING `+jobColumns,
		params.ID,
		params.Title,
		params.PriceLabel,
		params.ImageURL,
		params.Completeness,
		params.CreatedItemID,
	)
}

func (r *Repository) MarkNeedsReview(ctx context.Context, params ports.NeedsReviewJobParams) (domain.Job, error) {
	return r.updateResult(ctx, `
		UPDATE product_import_jobs
		SET status = 'needs_review',
			title = $2,
			price_label = $3,
			image_url = $4,
			completeness = $5,
			last_error = $6,
			error_code = $7,
			retryable = $8,
			locked_at = NULL
		WHERE id = $1::uuid AND status = 'processing'
		RETURNING `+jobColumns,
		params.ID,
		params.Title,
		params.PriceLabel,
		params.ImageURL,
		params.Completeness,
		params.LastError,
		params.ErrorCode,
		params.Retryable,
	)
}

func (r *Repository) MarkFailed(ctx context.Context, params ports.FailJobParams) (domain.Job, error) {
	return r.updateResult(ctx, `
		UPDATE product_import_jobs
		SET status = 'failed',
			title = $2,
			price_label = $3,
			image_url = $4,
			completeness = $5,
			last_error = $6,
			error_code = $7,
			retryable = $8,
			locked_at = NULL
		WHERE id = $1::uuid AND status = 'processing'
		RETURNING `+jobColumns,
		params.ID,
		params.Title,
		params.PriceLabel,
		params.ImageURL,
		params.Completeness,
		params.LastError,
		params.ErrorCode,
		params.Retryable,
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
	var lastAttemptedAt sql.NullTime
	var lastError sql.NullString
	var errorCode sql.NullString
	var title sql.NullString
	var priceLabel sql.NullString
	var imageURL sql.NullString
	var createdItemID sql.NullString
	var acknowledgedAt sql.NullTime
	var lockedAt sql.NullTime

	err := row.Scan(
		&job.ID,
		&job.UserID,
		&job.WishlistID,
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
		&imageURL,
		&job.Completeness,
		&createdItemID,
		&acknowledgedAt,
		&lockedAt,
		&job.CreatedAt,
		&job.UpdatedAt,
	)
	if err != nil {
		return domain.Job{}, err
	}

	job.LastAttemptedAt = nullableTime(lastAttemptedAt)
	job.LastError = nullableString(lastError)
	job.ErrorCode = nullableString(errorCode)
	job.Title = nullableString(title)
	job.PriceLabel = nullableString(priceLabel)
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
	image_url,
	completeness,
	created_item_id::text,
	acknowledged_at,
	locked_at,
	created_at,
	updated_at`
