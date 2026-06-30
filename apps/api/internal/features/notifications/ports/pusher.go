package ports

import (
	"context"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
)

// Pusher delivers a notification to a set of FCM device tokens. Push is
// best-effort/advisory — the durable notifications row is the source of truth.
// It returns the subset of tokens FCM reported as permanently invalid
// (unregistered / malformed) so the caller can prune them.
type Pusher interface {
	Push(ctx context.Context, tokens []string, n domain.Notification) (invalidTokens []string, err error)
}
