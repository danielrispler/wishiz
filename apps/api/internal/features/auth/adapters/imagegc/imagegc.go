// Package imagegc implements the auth ImageGarbageCollector: best-effort cleanup
// of a user's uploaded image objects when their account is hard-deleted. It reads
// the image URLs the user owns (wishlist covers + item images), keeps only the
// ones hosted in our own GCS bucket (external scraped retailer URLs are skipped),
// and deletes those objects. Every operation is best-effort — errors are logged
// and swallowed so account deletion never fails because image cleanup failed.
package imagegc

import (
	"context"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
)

// bucketStore is the slice of the storage uploader this collector needs: the
// uploader owns both halves of the URL<->key mapping, so the collector reuses its
// reverse (KeyFromPublicURL) instead of re-deriving the bucket prefix itself.
// *storage.GCSUploader satisfies it.
type bucketStore interface {
	KeyFromPublicURL(url string) (string, bool)
	Delete(ctx context.Context, key string) error
}

// Collector reads a user's owned uploaded-image keys and deletes the objects.
type Collector struct {
	pool   *pgxpool.Pool
	store  bucketStore
	logger *slog.Logger
}

// New builds a Collector backed by the shared uploader, whose KeyFromPublicURL
// owns the URL→key mapping (single source of truth — no prefix drift).
func New(pool *pgxpool.Pool, store bucketStore, logger *slog.Logger) *Collector {
	return &Collector{
		pool:   pool,
		store:  store,
		logger: logger,
	}
}

// CollectOwnedImageKeys returns the object keys for images the user owns that live
// in our bucket. Called before the cascade delete (while the rows still exist).
func (c *Collector) CollectOwnedImageKeys(ctx context.Context, userID string) []string {
	rows, err := c.pool.Query(ctx, `
		SELECT cover_image_url
		FROM wishlists
		WHERE owner_id = $1::uuid AND cover_image_url IS NOT NULL
		UNION ALL
		SELECT image_url
		FROM wishlist_items
		WHERE wishlist_id IN (SELECT id FROM wishlists WHERE owner_id = $1::uuid)
			AND image_url IS NOT NULL
	`, userID)
	if err != nil {
		c.logger.Error("collect owned image keys", "userID", userID, "error", err)
		return nil
	}
	defer rows.Close()

	var keys []string
	for rows.Next() {
		var url string
		if err := rows.Scan(&url); err != nil {
			c.logger.Error("scan owned image url", "userID", userID, "error", err)
			return keys
		}
		if key, ok := c.store.KeyFromPublicURL(url); ok {
			keys = append(keys, key)
		}
	}
	if err := rows.Err(); err != nil {
		c.logger.Error("iterate owned image urls", "userID", userID, "error", err)
	}
	return keys
}

// DeleteObjects removes each key, best-effort. Called after the user row is gone.
func (c *Collector) DeleteObjects(ctx context.Context, keys []string) {
	for _, key := range keys {
		if err := c.store.Delete(ctx, key); err != nil {
			c.logger.Error("delete owned image object", "key", key, "error", err)
		}
	}
}
