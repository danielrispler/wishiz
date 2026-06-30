// Package postgres implements ports.Repository over the Supabase transaction
// pooler. Every query uses inline $n::uuid casts and avoids server-prepared
// statement reuse so it is PgBouncer-safe (matches the sibling feature repos).
package postgres

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/ports"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/db"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const insertColumns = 9

func (r *Repository) Insert(ctx context.Context, notifications []domain.Notification) error {
	if len(notifications) == 0 {
		return nil
	}
	valueClauses := make([]string, 0, len(notifications))
	args := make([]any, 0, len(notifications)*insertColumns)
	for i, n := range notifications {
		base := i * insertColumns
		valueClauses = append(valueClauses, fmt.Sprintf(
			"($%d::uuid, $%d, $%d, $%d, $%d::uuid, $%d::uuid, $%d::uuid, $%d, $%d)",
			base+1, base+2, base+3, base+4, base+5, base+6, base+7, base+8, base+9,
		))
		args = append(args,
			n.UserID, n.Type, n.Title, n.Body,
			n.WishlistID, n.ItemID, n.ImportJobID, n.ReadAt, n.CreatedAt,
		)
	}
	query := `
		INSERT INTO notifications (
			user_id, type, title, body, wishlist_id, item_id, import_job_id, read_at, created_at
		) VALUES ` + strings.Join(valueClauses, ", ")
	if _, err := r.pool.Exec(ctx, query, args...); err != nil {
		return fmt.Errorf("insert notifications: %w", err)
	}
	return nil
}

func (r *Repository) ListByUser(
	ctx context.Context, userID string, limit, offset int,
) ([]domain.Notification, error) {
	if limit <= 0 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	rows, err := r.pool.Query(ctx, `
		SELECT
			id::text,
			user_id::text,
			type,
			title,
			body,
			wishlist_id::text,
			item_id::text,
			import_job_id::text,
			read_at,
			created_at
		FROM notifications
		WHERE user_id = $1::uuid
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list notifications: %w", err)
	}
	defer rows.Close()

	out := make([]domain.Notification, 0)
	for rows.Next() {
		var n domain.Notification
		if scanErr := rows.Scan(
			&n.ID, &n.UserID, &n.Type, &n.Title, &n.Body,
			&n.WishlistID, &n.ItemID, &n.ImportJobID, &n.ReadAt, &n.CreatedAt,
		); scanErr != nil {
			return nil, fmt.Errorf("scan notification: %w", scanErr)
		}
		out = append(out, n)
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate notifications: %w", err)
	}
	return out, nil
}

func (r *Repository) CountUnread(ctx context.Context, userID string) (int, error) {
	var count int
	if err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM notifications
		WHERE user_id = $1::uuid AND read_at IS NULL
	`, userID).Scan(&count); err != nil {
		return 0, fmt.Errorf("count unread notifications: %w", err)
	}
	return count, nil
}

func (r *Repository) MarkRead(ctx context.Context, userID, notificationID string) error {
	// COALESCE keeps the original read_at on a re-mark (idempotent); RowsAffected
	// is 0 only when the row is absent or not owned by userID.
	tag, err := r.pool.Exec(ctx, `
		UPDATE notifications
		SET read_at = COALESCE(read_at, NOW())
		WHERE id = $1::uuid AND user_id = $2::uuid
	`, notificationID, userID)
	if err != nil {
		return fmt.Errorf("mark notification read: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}
	return nil
}

func (r *Repository) MarkAllRead(ctx context.Context, userID string) (int64, error) {
	tag, err := r.pool.Exec(ctx, `
		UPDATE notifications
		SET read_at = NOW()
		WHERE user_id = $1::uuid AND read_at IS NULL
	`, userID)
	if err != nil {
		return 0, fmt.Errorf("mark all notifications read: %w", err)
	}
	return tag.RowsAffected(), nil
}

func (r *Repository) UpsertDeviceToken(ctx context.Context, userID, token, platform string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO device_tokens (user_id, token, platform)
		VALUES ($1::uuid, $2, $3)
		ON CONFLICT (token) DO UPDATE
		SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, last_seen_at = NOW()
	`, userID, token, platform)
	if err != nil {
		return fmt.Errorf("upsert device token: %w", err)
	}
	return nil
}

func (r *Repository) DeleteUserDeviceToken(ctx context.Context, userID, token string) error {
	_, err := r.pool.Exec(
		ctx, `DELETE FROM device_tokens WHERE token = $1 AND user_id = $2::uuid`, token, userID,
	)
	if err != nil {
		return fmt.Errorf("delete user device token: %w", err)
	}
	return nil
}

func (r *Repository) DeleteDeviceTokens(ctx context.Context, tokens []string) error {
	if len(tokens) == 0 {
		return nil
	}
	if _, err := r.pool.Exec(ctx, `DELETE FROM device_tokens WHERE token = ANY($1::text[])`, tokens); err != nil {
		return fmt.Errorf("delete device tokens: %w", err)
	}
	return nil
}

func (r *Repository) TokensForUsers(ctx context.Context, userIDs []string) ([]domain.DeviceToken, error) {
	if len(userIDs) == 0 {
		return []domain.DeviceToken{}, nil
	}
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, user_id::text, token, platform, created_at, last_seen_at
		FROM device_tokens
		WHERE user_id = ANY($1::uuid[])
	`, userIDs)
	if err != nil {
		return nil, fmt.Errorf("list device tokens: %w", err)
	}
	defer rows.Close()

	out := make([]domain.DeviceToken, 0)
	for rows.Next() {
		var t domain.DeviceToken
		if scanErr := rows.Scan(
			&t.ID, &t.UserID, &t.Token, &t.Platform, &t.CreatedAt, &t.LastSeenAt,
		); scanErr != nil {
			return nil, fmt.Errorf("scan device token: %w", scanErr)
		}
		out = append(out, t)
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate device tokens: %w", err)
	}
	return out, nil
}

func (r *Repository) NotificationsEnabled(ctx context.Context, userIDs []string) (map[string]bool, error) {
	out := make(map[string]bool, len(userIDs))
	if len(userIDs) == 0 {
		return out, nil
	}
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, notifications_enabled
		FROM app_users
		WHERE id = ANY($1::uuid[])
	`, userIDs)
	if err != nil {
		return nil, fmt.Errorf("load notification toggles: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var (
			id      string
			enabled bool
		)
		if scanErr := rows.Scan(&id, &enabled); scanErr != nil {
			return nil, fmt.Errorf("scan notification toggle: %w", scanErr)
		}
		out[id] = enabled
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate notification toggles: %w", err)
	}
	return out, nil
}

func (r *Repository) MutedUserIDs(
	ctx context.Context, wishlistID string, candidateUserIDs []string,
) (map[string]bool, error) {
	out := make(map[string]bool, len(candidateUserIDs))
	if len(candidateUserIDs) == 0 {
		return out, nil
	}
	rows, err := r.pool.Query(ctx, `
		SELECT user_id::text
		FROM notification_mutes
		WHERE wishlist_id = $1::uuid AND user_id = ANY($2::uuid[])
	`, wishlistID, candidateUserIDs)
	if err != nil {
		return nil, fmt.Errorf("load muted users: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id string
		if scanErr := rows.Scan(&id); scanErr != nil {
			return nil, fmt.Errorf("scan muted user: %w", scanErr)
		}
		out[id] = true
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate muted users: %w", err)
	}
	return out, nil
}

func (r *Repository) MutedWishlistIDs(ctx context.Context, userID string) ([]string, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT wishlist_id::text
		FROM notification_mutes
		WHERE user_id = $1::uuid
		ORDER BY wishlist_id
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("list muted wishlists: %w", err)
	}
	defer rows.Close()

	out := make([]string, 0)
	for rows.Next() {
		var id string
		if scanErr := rows.Scan(&id); scanErr != nil {
			return nil, fmt.Errorf("scan muted wishlist: %w", scanErr)
		}
		out = append(out, id)
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate muted wishlists: %w", err)
	}
	return out, nil
}

func (r *Repository) SetMute(ctx context.Context, userID, wishlistID string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO notification_mutes (user_id, wishlist_id)
		VALUES ($1::uuid, $2::uuid)
		ON CONFLICT (user_id, wishlist_id) DO NOTHING
	`, userID, wishlistID)
	if db.IsForeignKeyViolation(err) {
		return ports.ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("set notification mute: %w", err)
	}
	return nil
}

func (r *Repository) Unmute(ctx context.Context, userID, wishlistID string) error {
	if _, err := r.pool.Exec(ctx, `
		DELETE FROM notification_mutes
		WHERE user_id = $1::uuid AND wishlist_id = $2::uuid
	`, userID, wishlistID); err != nil {
		return fmt.Errorf("unmute notifications: %w", err)
	}
	return nil
}
