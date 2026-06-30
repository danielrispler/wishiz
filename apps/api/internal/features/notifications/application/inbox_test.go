package application

import (
	"context"
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/adapters/inmemory"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
)

// A user must not be able to deregister another user's device token. Before the
// fix the repo deleted by token alone, so any authenticated caller could kill an
// arbitrary device's push by supplying its raw token.
func TestDeregisterDeviceScopedToOwner(t *testing.T) {
	t.Parallel()
	repo := inmemory.NewRepository()
	svc := NewInboxService(repo)
	ctx := context.Background()
	_ = repo.UpsertDeviceToken(ctx, ownerID, "tok-owner", domain.PlatformIOS)

	// Attacker (memberID) tries to deregister the owner's token.
	if err := svc.DeregisterDevice(ctx, memberID, "tok-owner"); err != nil {
		t.Fatalf("deregister returned error: %v", err)
	}
	tokens, _ := repo.TokensForUsers(ctx, []string{ownerID})
	if len(tokens) != 1 {
		t.Fatalf("another user must not delete the owner's token; got %d tokens", len(tokens))
	}

	// The owner deregistering their own token succeeds.
	if err := svc.DeregisterDevice(ctx, ownerID, "tok-owner"); err != nil {
		t.Fatalf("owner deregister returned error: %v", err)
	}
	tokens, _ = repo.TokensForUsers(ctx, []string{ownerID})
	if len(tokens) != 0 {
		t.Fatalf("owner's own token should be deleted; got %d tokens", len(tokens))
	}
}
