// Package inmemory is a test-support adapter implementing ports.Repository with
// maps + a mutex. Production wiring uses the postgres adapter.
package inmemory

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/ports"
)

type Repository struct {
	mu            sync.Mutex
	seq           int
	notifications []domain.Notification
	tokens        []domain.DeviceToken
	mutes         map[string]map[string]bool // userID -> wishlistID -> muted
	disabled      map[string]bool            // userID -> master toggle OFF

	// FailInsert / FailPush-style seams for the swallow-error tests.
	insertErr error
}

func NewRepository() *Repository {
	return &Repository{
		mutes:    make(map[string]map[string]bool),
		disabled: make(map[string]bool),
	}
}

// --- test helpers ---

// DisableUser flips the master toggle OFF for a user (NotificationsEnabled=false).
func (r *Repository) DisableUser(userID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.disabled[userID] = true
}

// FailInsertWith makes the next and subsequent Insert calls return err (for the
// swallow-error test).
func (r *Repository) FailInsertWith(err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.insertErr = err
}

// All returns a copy of every stored notification (test inspection).
func (r *Repository) All() []domain.Notification {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]domain.Notification, len(r.notifications))
	copy(out, r.notifications)
	return out
}

// --- ports.Repository ---

func (r *Repository) Insert(_ context.Context, notifications []domain.Notification) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.insertErr != nil {
		return r.insertErr
	}
	for _, n := range notifications {
		r.seq++
		if n.ID == "" {
			n.ID = fmt.Sprintf("notif-%d", r.seq)
		}
		r.notifications = append(r.notifications, n)
	}
	return nil
}

func (r *Repository) ListByUser(_ context.Context, userID string, limit, offset int) ([]domain.Notification, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]domain.Notification, 0)
	for _, n := range r.notifications {
		if n.UserID == userID {
			out = append(out, n)
		}
	}
	sort.Slice(out, func(i, k int) bool { return out[i].CreatedAt.After(out[k].CreatedAt) })
	if offset > len(out) {
		offset = len(out)
	}
	out = out[offset:]
	if limit > 0 && limit < len(out) {
		out = out[:limit]
	}
	return out, nil
}

func (r *Repository) CountUnread(_ context.Context, userID string) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	count := 0
	for _, n := range r.notifications {
		if n.UserID == userID && n.ReadAt == nil {
			count++
		}
	}
	return count, nil
}

func (r *Repository) MarkRead(_ context.Context, userID, notificationID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i := range r.notifications {
		if r.notifications[i].ID == notificationID && r.notifications[i].UserID == userID {
			if r.notifications[i].ReadAt == nil {
				now := time.Now().UTC()
				r.notifications[i].ReadAt = &now
			}
			return nil
		}
	}
	return ports.ErrNotFound
}

func (r *Repository) MarkAllRead(_ context.Context, userID string) (int64, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	var count int64
	now := time.Now().UTC()
	for i := range r.notifications {
		if r.notifications[i].UserID == userID && r.notifications[i].ReadAt == nil {
			readAt := now
			r.notifications[i].ReadAt = &readAt
			count++
		}
	}
	return count, nil
}

func (r *Repository) UpsertDeviceToken(_ context.Context, userID, token, platform string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now().UTC()
	for i := range r.tokens {
		if r.tokens[i].Token == token {
			r.tokens[i].UserID = userID
			r.tokens[i].Platform = platform
			r.tokens[i].LastSeenAt = now
			return nil
		}
	}
	r.seq++
	r.tokens = append(r.tokens, domain.DeviceToken{
		ID:         fmt.Sprintf("token-%d", r.seq),
		UserID:     userID,
		Token:      token,
		Platform:   platform,
		CreatedAt:  now,
		LastSeenAt: now,
	})
	return nil
}

func (r *Repository) DeleteUserDeviceToken(_ context.Context, userID, token string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := r.tokens[:0]
	for _, t := range r.tokens {
		// Retain unless this is the caller's own token: the ownership predicate
		// mirrors the SQL guard so the IDOR is covered in unit tests too.
		if t.Token != token || t.UserID != userID {
			out = append(out, t)
		}
	}
	r.tokens = out
	return nil
}

func (r *Repository) DeleteDeviceTokens(_ context.Context, tokens []string) error {
	if len(tokens) == 0 {
		return nil
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	drop := make(map[string]bool, len(tokens))
	for _, tok := range tokens {
		drop[tok] = true
	}
	out := r.tokens[:0]
	for _, t := range r.tokens {
		if !drop[t.Token] {
			out = append(out, t)
		}
	}
	r.tokens = out
	return nil
}

func (r *Repository) TokensForUsers(_ context.Context, userIDs []string) ([]domain.DeviceToken, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	want := make(map[string]bool, len(userIDs))
	for _, id := range userIDs {
		want[id] = true
	}
	out := make([]domain.DeviceToken, 0)
	for _, t := range r.tokens {
		if want[t.UserID] {
			out = append(out, t)
		}
	}
	return out, nil
}

func (r *Repository) NotificationsEnabled(_ context.Context, userIDs []string) (map[string]bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make(map[string]bool, len(userIDs))
	for _, id := range userIDs {
		out[id] = !r.disabled[id]
	}
	return out, nil
}

func (r *Repository) MutedUserIDs(
	_ context.Context, wishlistID string, candidateUserIDs []string,
) (map[string]bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make(map[string]bool, len(candidateUserIDs))
	for _, id := range candidateUserIDs {
		if r.mutes[id][wishlistID] {
			out[id] = true
		}
	}
	return out, nil
}

func (r *Repository) MutedWishlistIDs(_ context.Context, userID string) ([]string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]string, 0)
	for wishlistID, muted := range r.mutes[userID] {
		if muted {
			out = append(out, wishlistID)
		}
	}
	sort.Strings(out)
	return out, nil
}

func (r *Repository) SetMute(_ context.Context, userID, wishlistID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.mutes[userID] == nil {
		r.mutes[userID] = make(map[string]bool)
	}
	r.mutes[userID][wishlistID] = true
	return nil
}

func (r *Repository) Unmute(_ context.Context, userID, wishlistID string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.mutes[userID] != nil {
		delete(r.mutes[userID], wishlistID)
	}
	return nil
}
