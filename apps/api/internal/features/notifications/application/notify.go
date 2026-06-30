package application

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/ports"
)

// pushTimeout bounds the detached FCM send kicked off after a notification is
// persisted (api/all roles run push off the request path).
const pushTimeout = 10 * time.Second

// NotifyService writes durable inbox rows and best-effort FCM pushes for the four
// notification events. Every method is void: it logs and swallows all errors so a
// notification failure can never roll back or fail the originating user action.
//
// emit ordering: resolve master toggle + per-list mute -> drop master-off
// recipients (no row at all) -> insert rows (muted ones already-read) -> push the
// unmuted recipients' tokens. The durable row is the source of truth; push is
// advisory.
type NotifyService struct {
	repo   ports.Repository
	pusher ports.Pusher
	logger *slog.Logger
	// async runs push on a detached goroutine (api/all, off the request path).
	// false sends inline (scraper/weekly-batch — no human waiting, and a detached
	// send could be frozen after the 2xx under scale-to-zero).
	async bool
	nowFn func() time.Time
}

func NewNotifyService(repo ports.Repository, pusher ports.Pusher, logger *slog.Logger, async bool) *NotifyService {
	if logger == nil {
		logger = slog.Default()
	}
	return &NotifyService{repo: repo, pusher: pusher, logger: logger, async: async, nowFn: time.Now}
}

// event is the internal representation emit() fans out to recipients.
type event struct {
	typ         string
	title       string
	body        string
	wishlistID  *string
	itemID      *string
	importJobID *string
	// applyMute gates the per-list mute lookup. False for import_settled, which
	// notifies the importer about their own action and has no list mute semantics.
	applyMute bool
}

// MemberJoined notifies the list owner that someone accepted an invite.
func (s *NotifyService) MemberJoined(
	ctx context.Context, recipientIDs []string, wishlistID, wishlistTitle, actorName string,
) {
	wl := wishlistID
	s.emit(ctx, recipientIDs, event{
		typ:        domain.TypeListMemberJoined,
		title:      actorName + " joined " + wishlistTitle,
		body:       actorName + " can now see and contribute to your list.",
		wishlistID: &wl,
		applyMute:  true,
	})
}

// ItemAdded notifies owner + members (minus the actor, computed by the caller)
// that an item was added to a shared list.
func (s *NotifyService) ItemAdded(
	ctx context.Context, recipientIDs []string, wishlistID, wishlistTitle, itemID, itemTitle, actorName string,
) {
	wl, it := wishlistID, itemID
	s.emit(ctx, recipientIDs, event{
		typ:        domain.TypeItemAdded,
		title:      actorName + " added an item to " + wishlistTitle,
		body:       itemTitle,
		wishlistID: &wl,
		itemID:     &it,
		applyMute:  true,
	})
}

// ItemPurchased notifies owner + members (minus the actor) that an item was
// marked purchased. The owner IS notified deliberately (collaborative lists).
func (s *NotifyService) ItemPurchased(
	ctx context.Context, recipientIDs []string, wishlistID, wishlistTitle, itemID, itemTitle, actorName string,
) {
	wl, it := wishlistID, itemID
	s.emit(ctx, recipientIDs, event{
		typ:        domain.TypeItemPurchased,
		title:      actorName + " purchased an item in " + wishlistTitle,
		body:       itemTitle,
		wishlistID: &wl,
		itemID:     &it,
		applyMute:  true,
	})
}

// ImportSettled notifies the importer that their import job reached a terminal
// status. wishlistID (if any) is stored for deep-linking but does not gate mute.
func (s *NotifyService) ImportSettled(
	ctx context.Context, userID, jobID string, wishlistID *string, status, productTitle string,
) {
	job := jobID
	title, body := importSettledCopy(status, productTitle)
	s.emit(ctx, []string{userID}, event{
		typ:         domain.TypeImportSettled,
		title:       title,
		body:        body,
		wishlistID:  cloneStringPtr(wishlistID),
		importJobID: &job,
		applyMute:   false,
	})
}

func (s *NotifyService) emit(ctx context.Context, recipientIDs []string, ev event) {
	recipients := dedupeNonEmpty(recipientIDs)
	if len(recipients) == 0 {
		return
	}

	// The master-toggle and per-list-mute lookups are independent (different tables),
	// so fetch them concurrently when both are needed — saving one round-trip on the
	// synchronous request path of every shared-list write.
	var (
		enabled              map[string]bool
		muted                = map[string]bool{}
		enabledErr, mutedErr error
	)
	if ev.applyMute && ev.wishlistID != nil {
		var wg sync.WaitGroup
		wg.Add(1)
		go func() {
			defer wg.Done()
			muted, mutedErr = s.repo.MutedUserIDs(ctx, *ev.wishlistID, recipients)
		}()
		enabled, enabledErr = s.repo.NotificationsEnabled(ctx, recipients)
		wg.Wait()
	} else {
		enabled, enabledErr = s.repo.NotificationsEnabled(ctx, recipients)
	}
	if enabledErr != nil {
		s.logger.Warn("notify: load master toggles failed", "type", ev.typ, "error", enabledErr)
		return
	}
	if mutedErr != nil {
		s.logger.Warn("notify: load mutes failed", "type", ev.typ, "error", mutedErr)
		return
	}

	now := s.nowFn().UTC()
	rows := make([]domain.Notification, 0, len(recipients))
	pushTo := make([]string, 0, len(recipients))
	for _, rid := range recipients {
		if !enabled[rid] {
			continue // master toggle OFF: the feature is dark — no row at all.
		}
		n := domain.Notification{
			UserID:      rid,
			Type:        ev.typ,
			Title:       ev.title,
			Body:        ev.body,
			WishlistID:  ev.wishlistID,
			ItemID:      ev.itemID,
			ImportJobID: ev.importJobID,
			CreatedAt:   now,
		}
		if muted[rid] {
			readAt := now // silent-but-visible: in inbox history, never badges/pushes.
			n.ReadAt = &readAt
		} else {
			pushTo = append(pushTo, rid)
		}
		rows = append(rows, n)
	}
	if len(rows) == 0 {
		return
	}

	if err := s.repo.Insert(ctx, rows); err != nil {
		s.logger.Warn("notify: insert failed", "type", ev.typ, "error", err)
		return // no durable row -> do not push (the row is the source of truth).
	}

	if s.pusher == nil || len(pushTo) == 0 {
		return
	}
	pushNotif := domain.Notification{
		Type:        ev.typ,
		Title:       ev.title,
		Body:        ev.body,
		WishlistID:  ev.wishlistID,
		ItemID:      ev.itemID,
		ImportJobID: ev.importJobID,
	}
	if s.async {
		detached := context.WithoutCancel(ctx)
		go func() {
			pctx, cancel := context.WithTimeout(detached, pushTimeout)
			defer cancel()
			s.push(pctx, pushTo, pushNotif)
		}()
		return
	}
	s.push(ctx, pushTo, pushNotif)
}

func (s *NotifyService) push(ctx context.Context, recipientIDs []string, n domain.Notification) {
	tokens, err := s.repo.TokensForUsers(ctx, recipientIDs)
	if err != nil {
		s.logger.Warn("notify: load device tokens failed", "type", n.Type, "error", err)
		return
	}
	if len(tokens) == 0 {
		return
	}
	strs := make([]string, len(tokens))
	for i, t := range tokens {
		strs[i] = t.Token
	}
	invalid, err := s.pusher.Push(ctx, strs, n)
	if err != nil {
		s.logger.Warn("notify: push failed", "type", n.Type, "error", err)
	}
	if len(invalid) > 0 {
		if derr := s.repo.DeleteDeviceTokens(ctx, invalid); derr != nil {
			s.logger.Warn("notify: prune invalid device tokens failed", "error", derr)
		}
	}
}

func importSettledCopy(status, productTitle string) (title, body string) {
	switch status {
	case "completed":
		return "Import ready", labelOrDefault(productTitle, "Your item was added to your wishlist.")
	case "needs_review":
		return "Import needs review", labelOrDefault(productTitle, "Tap to review and finish adding it.")
	default: // failed (and any unexpected terminal value)
		return "Import failed", labelOrDefault(productTitle, "We couldn't import that link.")
	}
}

func labelOrDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func dedupeNonEmpty(ids []string) []string {
	seen := make(map[string]bool, len(ids))
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func cloneStringPtr(value *string) *string {
	if value == nil {
		return nil
	}
	v := *value
	return &v
}
