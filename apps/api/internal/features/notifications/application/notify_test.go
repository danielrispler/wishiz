package application

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/adapters/inmemory"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
)

const (
	ownerID  = "11111111-1111-1111-1111-111111111111"
	memberID = "22222222-2222-2222-2222-222222222222"
	listID   = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	itemID   = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
	jobID    = "cccccccc-cccc-cccc-cccc-cccccccccccc"
)

type fakePusher struct {
	mu      sync.Mutex
	calls   [][]string
	notes   []domain.Notification
	invalid []string
	err     error
}

func (f *fakePusher) Push(_ context.Context, tokens []string, n domain.Notification) ([]string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	cp := append([]string(nil), tokens...)
	f.calls = append(f.calls, cp)
	f.notes = append(f.notes, n)
	return f.invalid, f.err
}

func (f *fakePusher) pushedTokens() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var all []string
	for _, c := range f.calls {
		all = append(all, c...)
	}
	return all
}

func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

// inline (async=false) so push runs synchronously and assertions are deterministic.
func newService(repo *inmemory.Repository, pusher *fakePusher) *NotifyService {
	return NewNotifyService(repo, pusher, discardLogger(), false)
}

func TestItemAddedFansOutToRecipients(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{}
	_ = repo.UpsertDeviceToken(context.Background(), ownerID, "tok-owner", domain.PlatformIOS)
	_ = repo.UpsertDeviceToken(context.Background(), memberID, "tok-member", domain.PlatformAndroid)
	svc := newService(repo, pusher)

	svc.ItemAdded(context.Background(), []string{ownerID, memberID}, listID, "Birthday", itemID, "Headphones", "Maya")

	rows := repo.All()
	if len(rows) != 2 {
		t.Fatalf("expected 2 rows, got %d", len(rows))
	}
	for _, n := range rows {
		if n.Type != domain.TypeItemAdded {
			t.Fatalf("unexpected type %q", n.Type)
		}
		if n.ReadAt != nil {
			t.Fatalf("expected unread row for %s", n.UserID)
		}
	}
	if count, _ := repo.CountUnread(context.Background(), ownerID); count != 1 {
		t.Fatalf("expected 1 unread for owner, got %d", count)
	}
	tokens := pusher.pushedTokens()
	if len(tokens) != 2 {
		t.Fatalf("expected push to 2 tokens, got %v", tokens)
	}
}

func TestMasterOffWritesNoRow(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{}
	repo.DisableUser(ownerID)
	_ = repo.UpsertDeviceToken(context.Background(), ownerID, "tok-owner", domain.PlatformIOS)
	_ = repo.UpsertDeviceToken(context.Background(), memberID, "tok-member", domain.PlatformAndroid)
	svc := newService(repo, pusher)

	svc.ItemAdded(context.Background(), []string{ownerID, memberID}, listID, "Birthday", itemID, "Headphones", "Maya")

	rows := repo.All()
	if len(rows) != 1 {
		t.Fatalf("expected 1 row (owner master-off dropped), got %d", len(rows))
	}
	if rows[0].UserID != memberID {
		t.Fatalf("expected the surviving row to belong to member, got %s", rows[0].UserID)
	}
	for _, tok := range pusher.pushedTokens() {
		if tok == "tok-owner" {
			t.Fatalf("master-off owner must not be pushed")
		}
	}
}

func TestMutedWritesPreReadRowNoPush(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{}
	_ = repo.SetMute(context.Background(), ownerID, listID)
	_ = repo.UpsertDeviceToken(context.Background(), ownerID, "tok-owner", domain.PlatformIOS)
	_ = repo.UpsertDeviceToken(context.Background(), memberID, "tok-member", domain.PlatformAndroid)
	svc := newService(repo, pusher)

	svc.ItemPurchased(context.Background(), []string{ownerID, memberID}, listID, "Birthday", itemID, "Headphones", "Maya")

	rows := repo.All()
	if len(rows) != 2 {
		t.Fatalf("expected 2 rows (muted still visible), got %d", len(rows))
	}
	for _, n := range rows {
		if n.UserID == ownerID && n.ReadAt == nil {
			t.Fatalf("muted owner row must be pre-read (read_at set)")
		}
		if n.UserID == memberID && n.ReadAt != nil {
			t.Fatalf("unmuted member row must be unread")
		}
	}
	if count, _ := repo.CountUnread(context.Background(), ownerID); count != 0 {
		t.Fatalf("muted row must not count toward badge, got %d", count)
	}
	for _, tok := range pusher.pushedTokens() {
		if tok == "tok-owner" {
			t.Fatalf("muted owner must not be pushed")
		}
	}
}

func TestPurchaseIncludesOwner(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	svc := newService(repo, &fakePusher{})

	svc.ItemPurchased(context.Background(), []string{ownerID, memberID}, listID, "Birthday", itemID, "Headphones", "Maya")

	var ownerNotified bool
	for _, n := range repo.All() {
		if n.UserID == ownerID && n.Type == domain.TypeItemPurchased {
			ownerNotified = true
		}
	}
	if !ownerNotified {
		t.Fatal("owner must be notified of a purchase (collaborative lists, deliberate)")
	}
}

func TestInvalidTokenCleanedUp(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{invalid: []string{"tok-member"}}
	_ = repo.UpsertDeviceToken(context.Background(), memberID, "tok-member", domain.PlatformAndroid)
	svc := newService(repo, pusher)

	svc.ItemAdded(context.Background(), []string{memberID}, listID, "Birthday", itemID, "Headphones", "Maya")

	tokens, _ := repo.TokensForUsers(context.Background(), []string{memberID})
	if len(tokens) != 0 {
		t.Fatalf("invalid token should have been deleted, got %v", tokens)
	}
}

func TestInsertErrorSwallowed(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{}
	repo.FailInsertWith(errors.New("boom"))
	svc := newService(repo, pusher)

	// Must not panic and must not push when the durable insert failed.
	svc.ItemAdded(context.Background(), []string{ownerID}, listID, "Birthday", itemID, "Headphones", "Maya")

	if len(repo.All()) != 0 {
		t.Fatal("no rows should persist on insert failure")
	}
	if len(pusher.pushedTokens()) != 0 {
		t.Fatal("must not push when insert failed")
	}
}

func TestPushErrorSwallowed(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{err: errors.New("fcm down")}
	_ = repo.UpsertDeviceToken(context.Background(), ownerID, "tok-owner", domain.PlatformIOS)
	svc := newService(repo, pusher)

	svc.ItemAdded(context.Background(), []string{ownerID}, listID, "Birthday", itemID, "Headphones", "Maya")

	if len(repo.All()) != 1 {
		t.Fatal("durable row must persist even when push errors")
	}
}

func TestImportSettledNotifiesImporterIgnoringMute(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	pusher := &fakePusher{}
	wl := listID
	// Even if the importer muted the destination list, import_settled still fires
	// (mute is skipped for import_settled — it has no list semantics).
	_ = repo.SetMute(context.Background(), ownerID, listID)
	_ = repo.UpsertDeviceToken(context.Background(), ownerID, "tok-owner", domain.PlatformIOS)
	svc := newService(repo, pusher)

	svc.ImportSettled(context.Background(), ownerID, jobID, &wl, "completed", "Headphones")

	rows := repo.All()
	if len(rows) != 1 {
		t.Fatalf("expected 1 import_settled row, got %d", len(rows))
	}
	if rows[0].ReadAt != nil {
		t.Fatal("import_settled must be unread (mute not applied)")
	}
	if rows[0].Type != domain.TypeImportSettled {
		t.Fatalf("unexpected type %q", rows[0].Type)
	}
	if len(pusher.pushedTokens()) != 1 {
		t.Fatal("import_settled should push to the importer")
	}
}
