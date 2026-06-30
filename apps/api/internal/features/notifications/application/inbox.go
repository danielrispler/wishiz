package application

import (
	"context"
	"errors"
	"regexp"
	"strings"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/ports"
)

var uuidPattern = regexp.MustCompile(
	"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
)

const (
	defaultListLimit = 50
	maxListLimit     = 100
)

// InboxService backs the user-facing notification HTTP handlers (list, badge,
// read-state, device registration, per-list mutes).
type InboxService struct {
	repo ports.Repository
}

func NewInboxService(repo ports.Repository) *InboxService {
	return &InboxService{repo: repo}
}

func (s *InboxService) List(ctx context.Context, userID string, limit, offset int) ([]domain.Notification, error) {
	if limit <= 0 || limit > maxListLimit {
		limit = defaultListLimit
	}
	if offset < 0 {
		offset = 0
	}
	return s.repo.ListByUser(ctx, userID, limit, offset)
}

func (s *InboxService) UnreadCount(ctx context.Context, userID string) (int, error) {
	return s.repo.CountUnread(ctx, userID)
}

func (s *InboxService) MarkRead(ctx context.Context, userID, notificationID string) error {
	if err := validateUUID("notificationId", notificationID); err != nil {
		return err
	}
	err := s.repo.MarkRead(ctx, userID, notificationID)
	if errors.Is(err, ports.ErrNotFound) {
		return NotFound()
	}
	return err
}

func (s *InboxService) MarkAllRead(ctx context.Context, userID string) (int, error) {
	count, err := s.repo.MarkAllRead(ctx, userID)
	return int(count), err
}

func (s *InboxService) RegisterDevice(ctx context.Context, userID, token, platform string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return ValidationError("token", "token is required")
	}
	platform = strings.TrimSpace(strings.ToLower(platform))
	if platform != domain.PlatformIOS && platform != domain.PlatformAndroid {
		return ValidationError("platform", "platform must be ios or android")
	}
	return s.repo.UpsertDeviceToken(ctx, userID, token, platform)
}

func (s *InboxService) DeregisterDevice(ctx context.Context, userID, token string) error {
	token = strings.TrimSpace(token)
	if token == "" {
		return ValidationError("token", "token is required")
	}
	return s.repo.DeleteUserDeviceToken(ctx, userID, token)
}

func (s *InboxService) ListMutes(ctx context.Context, userID string) ([]string, error) {
	return s.repo.MutedWishlistIDs(ctx, userID)
}

func (s *InboxService) Mute(ctx context.Context, userID, wishlistID string) error {
	if err := validateUUID("wishlistId", wishlistID); err != nil {
		return err
	}
	err := s.repo.SetMute(ctx, userID, wishlistID)
	if errors.Is(err, ports.ErrNotFound) {
		return NotFound()
	}
	return err
}

func (s *InboxService) Unmute(ctx context.Context, userID, wishlistID string) error {
	if err := validateUUID("wishlistId", wishlistID); err != nil {
		return err
	}
	return s.repo.Unmute(ctx, userID, wishlistID)
}

func validateUUID(field, value string) error {
	if !uuidPattern.MatchString(value) {
		return ValidationError(field, field+" must be a valid UUID")
	}
	return nil
}
