package ports

import (
	"context"
	"errors"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
)

var ErrNotFound = errors.New("notifications repository: not found")

// Repository persists notifications, device tokens and per-list mutes. All
// queries are pooler-safe ($n::uuid casts, no server-prepared reuse).
type Repository interface {
	// Insert writes a batch of notifications in one round-trip. The rows carry
	// their own ReadAt (nil = unread, set = silent-but-visible/muted).
	Insert(ctx context.Context, notifications []domain.Notification) error
	ListByUser(ctx context.Context, userID string, limit, offset int) ([]domain.Notification, error)
	CountUnread(ctx context.Context, userID string) (int, error)
	// MarkRead marks one notification read; ErrNotFound when it is absent or not
	// owned by userID.
	MarkRead(ctx context.Context, userID, notificationID string) error
	MarkAllRead(ctx context.Context, userID string) (int64, error)

	// UpsertDeviceToken registers (or re-points) a device token to userID.
	UpsertDeviceToken(ctx context.Context, userID, token, platform string) error
	// DeleteUserDeviceToken removes a token only when it belongs to userID. The
	// ownership predicate is the IDOR guard for the user-facing deregister route.
	DeleteUserDeviceToken(ctx context.Context, userID, token string) error
	// DeleteDeviceTokens prunes FCM-dead tokens in one round-trip. It is an
	// internal cleanup path (no user input), so it scopes by token only — push()
	// reports invalid tokens across many users with no per-token owner in scope.
	DeleteDeviceTokens(ctx context.Context, tokens []string) error
	TokensForUsers(ctx context.Context, userIDs []string) ([]domain.DeviceToken, error)

	// NotificationsEnabled reports the master toggle (app_users.notifications_enabled)
	// for each requested user. Reading app_users here keeps the module self-contained.
	NotificationsEnabled(ctx context.Context, userIDs []string) (map[string]bool, error)

	// MutedUserIDs returns, of candidateUserIDs, the subset that has muted wishlistID.
	MutedUserIDs(ctx context.Context, wishlistID string, candidateUserIDs []string) (map[string]bool, error)
	MutedWishlistIDs(ctx context.Context, userID string) ([]string, error)
	SetMute(ctx context.Context, userID, wishlistID string) error
	Unmute(ctx context.Context, userID, wishlistID string) error
}
