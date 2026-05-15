package application

import (
	"context"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/ports"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
)

func TestServicePatchWishlistPreservesOmittedFieldsAndClearsNullableValues(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	cover := "https://example.com/original.jpg"
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:            wishlistID1,
		OwnerID:       ownerID,
		Title:         "Original",
		Description:   "Warm lighting",
		Year:          2026,
		CoverImageURL: &cover,
		CreatedAt:     fixedTime,
		UpdatedAt:     fixedTime,
		Items:         []domain.WishlistItem{},
	}

	service := NewService(repo)

	wishlist, err := service.Patch(userContext(ownerID, "owner@example.com"), wishlistID1, &PatchWishlistInput{
		Title:         PatchField[string]{Set: true, Value: "  Updated Title  "},
		CoverImageURL: PatchField[*string]{Set: true, Value: nil},
	})
	if err != nil {
		t.Fatalf("Patch returned error: %v", err)
	}

	if wishlist.Title != "Updated Title" {
		t.Fatalf("expected trimmed title, got %q", wishlist.Title)
	}
	if wishlist.CoverImageURL != nil {
		t.Fatalf("expected cover image to be cleared, got %v", *wishlist.CoverImageURL)
	}
	if wishlist.Year != 2026 {
		t.Fatalf("expected year to remain unchanged, got %d", wishlist.Year)
	}
}

func TestServicePatchItemPurchasedStatusRefreshesPurchasedAt(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = wishlistWithItems(ownerID, []domain.WishlistItem{
		{
			ID:        itemID1,
			Title:     "Stoneware plates",
			Rank:      1,
			Priority:  domain.ItemPriorityMedium,
			Status:    domain.ItemStatusSaved,
			CreatedAt: fixedTime,
			UpdatedAt: fixedTime,
		},
	})

	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime.Add(24 * time.Hour) }

	item, err := service.PatchItem(userContext(ownerID, "owner@example.com"), wishlistID1, itemID1, &PatchItemInput{
		Status: PatchField[string]{Set: true, Value: domain.ItemStatusPurchased},
	})
	if err != nil {
		t.Fatalf("PatchItem returned error: %v", err)
	}
	if item.PurchasedAt == nil {
		t.Fatalf("expected purchasedAt to be set")
	}
	if !item.PurchasedAt.Equal(fixedTime.Add(24 * time.Hour)) {
		t.Fatalf("expected purchasedAt to match service clock, got %v", item.PurchasedAt)
	}

	item, err = service.PatchItem(userContext(ownerID, "owner@example.com"), wishlistID1, itemID1, &PatchItemInput{
		Status: PatchField[string]{Set: true, Value: domain.ItemStatusSaved},
	})
	if err != nil {
		t.Fatalf("PatchItem reset returned error: %v", err)
	}
	if item.PurchasedAt != nil {
		t.Fatalf("expected purchasedAt to clear when status returns to saved")
	}
}

func TestServicePatchItemPreservesPurchasedAtWhenStatusStaysPurchased(t *testing.T) {
	t.Parallel()
	originalPurchasedAt := fixedTime.Add(-6 * time.Hour)
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = wishlistWithItems(ownerID, []domain.WishlistItem{
		{
			ID:          itemID1,
			Title:       "Stoneware plates",
			Rank:        1,
			Priority:    domain.ItemPriorityMedium,
			Status:      domain.ItemStatusPurchased,
			PurchasedAt: &originalPurchasedAt,
			CreatedAt:   fixedTime,
			UpdatedAt:   fixedTime,
		},
	})

	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime.Add(24 * time.Hour) }

	item, err := service.PatchItem(userContext(ownerID, "owner@example.com"), wishlistID1, itemID1, &PatchItemInput{
		Status: PatchField[string]{Set: true, Value: domain.ItemStatusPurchased},
	})
	if err != nil {
		t.Fatalf("PatchItem returned error: %v", err)
	}
	if item.PurchasedAt == nil {
		t.Fatalf("expected purchasedAt to remain set")
	}
	if !item.PurchasedAt.Equal(originalPurchasedAt) {
		t.Fatalf("expected purchasedAt to stay %v, got %v", originalPurchasedAt, *item.PurchasedAt)
	}
}

func TestServiceReorderItemsUsesSubsetOrderingRules(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = wishlistWithItems(ownerID, []domain.WishlistItem{
		{ID: itemID1, Title: "Lamp", Rank: 1, Priority: domain.ItemPriorityMedium, Status: domain.ItemStatusSaved, CreatedAt: fixedTime, UpdatedAt: fixedTime},
		{ID: itemID2, Title: "Monitor", Rank: 2, Priority: domain.ItemPriorityMedium, Status: domain.ItemStatusSaved, CreatedAt: fixedTime, UpdatedAt: fixedTime},
		{ID: itemID3, Title: "Keyboard", Rank: 3, Priority: domain.ItemPriorityMedium, Status: domain.ItemStatusSaved, CreatedAt: fixedTime, UpdatedAt: fixedTime},
	})

	service := NewService(repo)

	wishlist, err := service.ReorderItems(userContext(ownerID, "owner@example.com"), wishlistID1, []string{itemID3, "not-a-real-item", itemID3, itemID1})
	if err != nil {
		t.Fatalf("ReorderItems returned error: %v", err)
	}

	if len(wishlist.Items) != 3 {
		t.Fatalf("expected 3 items, got %d", len(wishlist.Items))
	}
	if wishlist.Items[0].ID != itemID3 || wishlist.Items[0].Rank != 1 {
		t.Fatalf("expected first item to be %s with rank 1, got %+v", itemID3, wishlist.Items[0])
	}
	if wishlist.Items[1].ID != itemID1 || wishlist.Items[1].Rank != 2 {
		t.Fatalf("expected second item to be %s with rank 2, got %+v", itemID1, wishlist.Items[1])
	}
	if wishlist.Items[2].ID != itemID2 || wishlist.Items[2].Rank != 3 {
		t.Fatalf("expected remaining item to be appended with rank 3, got %+v", wishlist.Items[2])
	}
}

func TestServiceGetByIDRejectsNonMemberAccess(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Private",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members:   []domain.WishlistMember{},
		Items:     []domain.WishlistItem{},
	}

	service := NewService(repo)

	_, err := service.GetByID(userContext(viewerID, "viewer@example.com"), wishlistID1)
	if err == nil {
		t.Fatalf("expected access error")
	}

	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeWishlistNotFound {
		t.Fatalf("expected wishlist not found error, got %+v", err)
	}
}

func TestServiceListIncludesOwnedAndMemberWishlists(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Owned",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
	}
	repo.wishlists[wishlistID2] = domain.Wishlist{
		ID:        wishlistID2,
		OwnerID:   otherOwnerID,
		Title:     "Member List",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID2, UserID: viewerID, Email: "viewer@example.com", Role: domain.MemberRoleViewer},
		},
	}
	repo.wishlists[wishlistID3] = domain.Wishlist{
		ID:        wishlistID3,
		OwnerID:   otherOwnerID,
		Title:     "Not For Viewer",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID3, UserID: ownerID, Email: "owner@example.com", Role: domain.MemberRoleViewer},
		},
	}

	service := NewService(repo)

	wishlists, err := service.List(userContext(viewerID, "viewer@example.com"))
	if err != nil {
		t.Fatalf("List returned error: %v", err)
	}
	if len(wishlists) != 1 {
		t.Fatalf("expected 1 visible wishlist, got %d", len(wishlists))
	}
	if wishlists[0].ID != wishlistID2 {
		t.Fatalf("expected member wishlist, got %s", wishlists[0].ID)
	}
}

func TestServiceCreateInviteReturnsSingleUseToken(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
	}
	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime }

	invite, err := service.CreateInvite(userContext(ownerID, "owner@example.com"), wishlistID1, &CreateInviteInput{
		Email: "  Viewer@Example.com ",
		Role:  domain.MemberRoleEditor,
	})
	if err != nil {
		t.Fatalf("CreateInvite returned error: %v", err)
	}
	if invite.Email != "viewer@example.com" {
		t.Fatalf("expected normalized email, got %q", invite.Email)
	}
	if invite.Role != domain.MemberRoleEditor {
		t.Fatalf("expected editor role, got %q", invite.Role)
	}
	if invite.Token == "" {
		t.Fatalf("expected invite token to be returned")
	}
	if !invite.ExpiresAt.Equal(fixedTime.Add(inviteDuration)) {
		t.Fatalf("expected default expiry, got %v", invite.ExpiresAt)
	}
}

func TestServiceJoinAcceptsInviteAndAddsMember(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	invite := domain.WishlistInvite{
		ID:         inviteID1,
		WishlistID: wishlistID1,
		Email:      "viewer@example.com",
		Role:       domain.MemberRoleViewer,
		ExpiresAt:  fixedTime.Add(time.Hour),
		CreatedAt:  fixedTime,
		UpdatedAt:  fixedTime,
	}
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Invites:   []domain.WishlistInvite{invite},
	}
	repo.inviteTokenHashes[inviteID1] = tokenHash("raw-token")
	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime }

	wishlist, err := service.Join(userContext(viewerID, "viewer@example.com"), wishlistID1, &JoinWishlistInput{Token: "raw-token"})
	if err != nil {
		t.Fatalf("Join returned error: %v", err)
	}
	if len(wishlist.Members) != 1 {
		t.Fatalf("expected one member, got %d", len(wishlist.Members))
	}
	if wishlist.Members[0].UserID != viewerID || wishlist.Members[0].Role != domain.MemberRoleViewer {
		t.Fatalf("unexpected member: %+v", wishlist.Members[0])
	}
	if repo.wishlists[wishlistID1].Invites[0].AcceptedAt == nil {
		t.Fatalf("expected invite accepted_at to be set")
	}
}

func TestServiceJoinRejectsLegacyShareToken(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:         wishlistID1,
		OwnerID:    ownerID,
		Title:      "Shared List",
		Year:       2026,
		ShareToken: "permanent-token",
		CreatedAt:  fixedTime,
		UpdatedAt:  fixedTime,
		Members:    []domain.WishlistMember{},
	}
	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime }

	_, err := service.Join(userContext(viewerID, "viewer@example.com"), wishlistID1, &JoinWishlistInput{Token: "permanent-token"})
	if err == nil {
		t.Fatalf("expected share token join to fail")
	}
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeWishlistNotFound {
		t.Fatalf("expected wishlist not found error, got %+v", err)
	}
}

func TestServiceJoinRequiresInviteToken(t *testing.T) {
	t.Parallel()
	service := NewService(newFakeRepository())

	_, err := service.Join(userContext(viewerID, "viewer@example.com"), wishlistID1, &JoinWishlistInput{Token: "   "})
	if err == nil {
		t.Fatalf("expected validation error")
	}
	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeValidation || appErr.Field != "token" {
		t.Fatalf("expected token validation error, got %+v", appErr)
	}
}

func TestServiceCreateValidatesYear(t *testing.T) {
	t.Parallel()
	service := NewService(newFakeRepository())

	_, err := service.Create(userContext(ownerID, "owner@example.com"), &CreateWishlistInput{
		Title: "Reading Corner",
		Year:  1999,
	})
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeValidation || appErr.Field != "year" {
		t.Fatalf("expected year validation error, got %+v", err)
	}
}

func TestServiceCreateInviteAllowsEditor(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID1, UserID: editorID, Email: "editor@example.com", Role: domain.MemberRoleEditor},
		},
	}
	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime }

	_, err := service.CreateInvite(userContext(editorID, "editor@example.com"), wishlistID1, &CreateInviteInput{
		Email: "newperson@example.com",
		Role:  domain.MemberRoleViewer,
	})
	if err != nil {
		t.Fatalf("expected editor to create invite, got error: %v", err)
	}
}

func TestServiceCreateInviteRejectsViewer(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID1, UserID: viewerID, Email: "viewer@example.com", Role: domain.MemberRoleViewer},
		},
	}
	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime }

	_, err := service.CreateInvite(userContext(viewerID, "viewer@example.com"), wishlistID1, &CreateInviteInput{
		Email: "newperson@example.com",
		Role:  domain.MemberRoleViewer,
	})
	if err == nil {
		t.Fatalf("expected viewer to be rejected from creating invite")
	}
}

func TestServiceRemoveMemberOwnerCan(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID1, UserID: viewerID, Email: "viewer@example.com", Role: domain.MemberRoleViewer},
		},
	}
	service := NewService(repo)

	if err := service.RemoveMember(userContext(ownerID, "owner@example.com"), wishlistID1, viewerID); err != nil {
		t.Fatalf("expected owner to remove member, got error: %v", err)
	}
}

func TestServiceRemoveMemberEditorCannot(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID1, UserID: editorID, Email: "editor@example.com", Role: domain.MemberRoleEditor},
			{WishlistID: wishlistID1, UserID: viewerID, Email: "viewer@example.com", Role: domain.MemberRoleViewer},
		},
	}
	service := NewService(repo)

	if err := service.RemoveMember(userContext(editorID, "editor@example.com"), wishlistID1, viewerID); err == nil {
		t.Fatalf("expected editor to be rejected from removing member")
	}
}

func TestServiceUpdateMemberRoleOwnerCan(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID1, UserID: viewerID, Email: "viewer@example.com", Role: domain.MemberRoleViewer},
		},
	}
	service := NewService(repo)

	if err := service.UpdateMemberRole(userContext(ownerID, "owner@example.com"), wishlistID1, viewerID, &PatchWishlistMemberInput{Role: domain.MemberRoleEditor}); err != nil {
		t.Fatalf("expected owner to update role, got error: %v", err)
	}
	if repo.wishlists[wishlistID1].Members[0].Role != domain.MemberRoleEditor {
		t.Fatalf("expected role to be updated to editor")
	}
}

func TestServiceUpdateMemberRoleEditorCannot(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members: []domain.WishlistMember{
			{WishlistID: wishlistID1, UserID: editorID, Email: "editor@example.com", Role: domain.MemberRoleEditor},
			{WishlistID: wishlistID1, UserID: viewerID, Email: "viewer@example.com", Role: domain.MemberRoleViewer},
		},
	}
	service := NewService(repo)

	if err := service.UpdateMemberRole(userContext(editorID, "editor@example.com"), wishlistID1, viewerID, &PatchWishlistMemberInput{Role: domain.MemberRoleEditor}); err == nil {
		t.Fatalf("expected editor to be rejected from updating member role")
	}
}

func TestServiceUpdateMemberRoleBlocksSelf(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members:   []domain.WishlistMember{},
	}
	service := NewService(repo)

	err := service.UpdateMemberRole(userContext(ownerID, "owner@example.com"), wishlistID1, ownerID, &PatchWishlistMemberInput{Role: domain.MemberRoleViewer})
	if err == nil {
		t.Fatalf("expected owner to be blocked from changing own role")
	}
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeValidation {
		t.Fatalf("expected validation error, got %+v", err)
	}
}

func TestServiceUpdateMemberRoleMissingMemberReturnsNotFound(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		OwnerID:   ownerID,
		Title:     "Party",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Members:   []domain.WishlistMember{},
	}
	service := NewService(repo)

	err := service.UpdateMemberRole(userContext(ownerID, "owner@example.com"), wishlistID1, viewerID, &PatchWishlistMemberInput{Role: domain.MemberRoleEditor})
	if err == nil {
		t.Fatalf("expected not found error")
	}
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeWishlistNotFound {
		t.Fatalf("expected wishlist not found error, got %+v", err)
	}
}

const (
	ownerID      = "99999999-9999-9999-9999-999999999999"
	otherOwnerID = "88888888-8888-8888-8888-888888888888"
	editorID     = "66666666-6666-6666-6666-666666666666"
	viewerID     = "77777777-7777-7777-7777-777777777777"
	wishlistID1  = "11111111-1111-1111-1111-111111111111"
	wishlistID2  = "22222222-2222-2222-2222-222222222222"
	wishlistID3  = "33333333-3333-3333-3333-333333333333"
	inviteID1    = "44444444-4444-4444-4444-444444444444"
	itemID1      = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	itemID2      = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
	itemID3      = "cccccccc-cccc-cccc-cccc-cccccccccccc"
)

var fixedTime = time.Date(2026, 3, 29, 12, 0, 0, 0, time.UTC)

type fakeRepository struct {
	wishlists         map[string]domain.Wishlist
	inviteTokenHashes map[string]string
}

func newFakeRepository() *fakeRepository {
	return &fakeRepository{
		wishlists:         map[string]domain.Wishlist{},
		inviteTokenHashes: map[string]string{},
	}
}

func (r *fakeRepository) List(_ context.Context, requestUserID string) ([]domain.Wishlist, error) {
	result := make([]domain.Wishlist, 0, len(r.wishlists))
	for _, wishlist := range r.wishlists {
		if wishlist.OwnerID == requestUserID {
			result = append(result, cloneWishlist(wishlist))
			continue
		}
		for _, member := range wishlist.Members {
			if member.UserID == requestUserID {
				result = append(result, cloneWishlist(wishlist))
				break
			}
		}
	}
	return result, nil
}

func (r *fakeRepository) GetByID(_ context.Context, id string) (domain.Wishlist, error) {
	wishlist, ok := r.wishlists[id]
	if !ok {
		return domain.Wishlist{}, ports.ErrNotFound
	}

	return cloneWishlist(wishlist), nil
}

func (r *fakeRepository) Create(_ context.Context, params ports.CreateWishlistParams) (domain.Wishlist, error) {
	wishlist := domain.Wishlist{
		ID:            wishlistID1,
		OwnerID:       params.OwnerID,
		Title:         params.Title,
		Description:   params.Description,
		Year:          params.Year,
		CoverImageURL: cloneString(params.CoverImageURL),
		CreatedAt:     fixedTime,
		UpdatedAt:     fixedTime,
		Members:       []domain.WishlistMember{},
		Invites:       []domain.WishlistInvite{},
		Items:         []domain.WishlistItem{},
	}

	r.wishlists[wishlist.ID] = wishlist
	return cloneWishlist(wishlist), nil
}

func (r *fakeRepository) Update(_ context.Context, params ports.UpdateWishlistParams) (domain.Wishlist, error) {
	wishlist, ok := r.wishlists[params.ID]
	if !ok {
		return domain.Wishlist{}, ports.ErrNotFound
	}

	wishlist.Title = params.Title
	wishlist.Description = params.Description
	wishlist.Year = params.Year
	wishlist.CoverImageURL = cloneString(params.CoverImageURL)
	wishlist.UpdatedAt = fixedTime.Add(time.Hour)
	r.wishlists[params.ID] = wishlist

	return cloneWishlist(wishlist), nil
}

func (r *fakeRepository) Delete(_ context.Context, id string) error {
	if _, ok := r.wishlists[id]; !ok {
		return ports.ErrNotFound
	}

	delete(r.wishlists, id)
	return nil
}

func (r *fakeRepository) Archive(_ context.Context, id string) (domain.Wishlist, error) {
	wishlist, ok := r.wishlists[id]
	if !ok {
		return domain.Wishlist{}, ports.ErrNotFound
	}

	wishlist.IsArchived = true
	r.wishlists[id] = wishlist
	return cloneWishlist(wishlist), nil
}

func (r *fakeRepository) Restore(_ context.Context, id string) (domain.Wishlist, error) {
	wishlist, ok := r.wishlists[id]
	if !ok {
		return domain.Wishlist{}, ports.ErrNotFound
	}

	wishlist.IsArchived = false
	r.wishlists[id] = wishlist
	return cloneWishlist(wishlist), nil
}

func (r *fakeRepository) AddItem(_ context.Context, params ports.AddItemParams) (domain.WishlistItem, error) {
	wishlist, ok := r.wishlists[params.WishlistID]
	if !ok {
		return domain.WishlistItem{}, ports.ErrNotFound
	}

	item := domain.WishlistItem{
		ID:          itemID1,
		Title:       params.Title,
		Rank:        len(wishlist.Items) + 1,
		Notes:       cloneString(params.Notes),
		PriceLabel:  cloneString(params.PriceLabel),
		Priority:    params.Priority,
		Status:      params.Status,
		ImageURL:    cloneString(params.ImageURL),
		ProductURL:  cloneString(params.ProductURL),
		PurchasedAt: cloneTime(params.PurchasedAt),
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
	}

	wishlist.Items = append(wishlist.Items, item)
	r.wishlists[params.WishlistID] = wishlist

	return cloneItem(item), nil
}

func (r *fakeRepository) UpdateItem(_ context.Context, params ports.UpdateItemParams) (domain.WishlistItem, error) {
	wishlist, ok := r.wishlists[params.WishlistID]
	if !ok {
		return domain.WishlistItem{}, ports.ErrNotFound
	}

	for index, item := range wishlist.Items {
		if item.ID != params.ItemID {
			continue
		}

		item.Title = params.Title
		item.Rank = params.Rank
		item.Notes = cloneString(params.Notes)
		item.PriceLabel = cloneString(params.PriceLabel)
		item.Priority = params.Priority
		item.Status = params.Status
		item.ImageURL = cloneString(params.ImageURL)
		item.ProductURL = cloneString(params.ProductURL)
		item.PurchasedAt = cloneTime(params.PurchasedAt)
		item.UpdatedAt = fixedTime.Add(2 * time.Hour)
		wishlist.Items[index] = item
		r.wishlists[params.WishlistID] = wishlist

		return cloneItem(item), nil
	}

	return domain.WishlistItem{}, ports.ErrNotFound
}

func (r *fakeRepository) DeleteItem(_ context.Context, wishlistID string, itemID string) error {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return ports.ErrNotFound
	}

	nextItems := make([]domain.WishlistItem, 0, len(wishlist.Items))
	found := false
	for _, item := range wishlist.Items {
		if item.ID == itemID {
			found = true
			continue
		}
		nextItems = append(nextItems, item)
	}
	if !found {
		return ports.ErrNotFound
	}

	wishlist.Items = nextItems
	r.wishlists[wishlistID] = wishlist
	return nil
}

func (r *fakeRepository) ReorderItems(_ context.Context, wishlistID string, orderedItemIDs []string) error {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return ports.ErrNotFound
	}

	itemByID := make(map[string]domain.WishlistItem, len(wishlist.Items))
	for _, item := range wishlist.Items {
		itemByID[item.ID] = item
	}

	nextItems := make([]domain.WishlistItem, 0, len(wishlist.Items))
	seen := make(map[string]struct{}, len(wishlist.Items))
	for _, itemID := range orderedItemIDs {
		item, ok := itemByID[itemID]
		if !ok {
			continue
		}
		if _, exists := seen[itemID]; exists {
			continue
		}

		item.Rank = len(nextItems) + 1
		nextItems = append(nextItems, item)
		seen[itemID] = struct{}{}
	}

	for _, item := range wishlist.Items {
		if _, exists := seen[item.ID]; exists {
			continue
		}
		item.Rank = len(nextItems) + 1
		nextItems = append(nextItems, item)
	}

	wishlist.Items = nextItems
	r.wishlists[wishlistID] = wishlist
	return nil
}

func (r *fakeRepository) CreateInvite(_ context.Context, params ports.CreateInviteParams) (domain.WishlistInvite, error) {
	wishlist, ok := r.wishlists[params.WishlistID]
	if !ok {
		return domain.WishlistInvite{}, ports.ErrNotFound
	}

	invitedBy := params.InvitedByUserID
	invite := domain.WishlistInvite{
		ID:              inviteID1,
		WishlistID:      params.WishlistID,
		Email:           params.Email,
		Role:            params.Role,
		InvitedByUserID: &invitedBy,
		ExpiresAt:       params.ExpiresAt,
		CreatedAt:       fixedTime,
		UpdatedAt:       fixedTime,
	}
	wishlist.Invites = []domain.WishlistInvite{invite}
	r.inviteTokenHashes[invite.ID] = params.TokenHash
	r.wishlists[params.WishlistID] = wishlist
	return invite, nil
}

func (r *fakeRepository) DeleteInvite(_ context.Context, wishlistID string, inviteID string) error {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return ports.ErrNotFound
	}
	next := make([]domain.WishlistInvite, 0, len(wishlist.Invites))
	found := false
	for _, invite := range wishlist.Invites {
		if invite.ID == inviteID {
			found = true
			continue
		}
		next = append(next, invite)
	}
	if !found {
		return ports.ErrNotFound
	}
	wishlist.Invites = next
	r.wishlists[wishlistID] = wishlist
	return nil
}

func (r *fakeRepository) GetInviteByTokenHash(_ context.Context, wishlistID string, tokenHash string) (domain.WishlistInvite, error) {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return domain.WishlistInvite{}, ports.ErrNotFound
	}
	for _, invite := range wishlist.Invites {
		if r.inviteTokenHashes[invite.ID] == tokenHash {
			return cloneInvite(invite), nil
		}
	}
	return domain.WishlistInvite{}, ports.ErrNotFound
}

func (r *fakeRepository) AcceptInvite(_ context.Context, params ports.AcceptInviteParams) error {
	wishlist, ok := r.wishlists[params.WishlistID]
	if !ok {
		return ports.ErrNotFound
	}
	for index, invite := range wishlist.Invites {
		if invite.ID == params.InviteID {
			acceptedAt := params.AcceptedAt
			invite.AcceptedAt = &acceptedAt
			wishlist.Invites[index] = invite
			wishlist.Members = append(wishlist.Members, domain.WishlistMember{
				WishlistID: params.WishlistID,
				UserID:     params.UserID,
				Email:      "viewer@example.com",
				FullName:   "Viewer",
				Role:       params.Role,
				CreatedAt:  params.AcceptedAt,
				UpdatedAt:  params.AcceptedAt,
			})
			r.wishlists[params.WishlistID] = wishlist
			return nil
		}
	}
	return ports.ErrNotFound
}

func (r *fakeRepository) RemoveMember(_ context.Context, wishlistID string, userID string) error {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return ports.ErrNotFound
	}
	next := make([]domain.WishlistMember, 0, len(wishlist.Members))
	found := false
	for _, member := range wishlist.Members {
		if member.UserID == userID {
			found = true
			continue
		}
		next = append(next, member)
	}
	if !found {
		return ports.ErrNotFound
	}
	wishlist.Members = next
	r.wishlists[wishlistID] = wishlist
	return nil
}

func (r *fakeRepository) UpdateMemberRole(_ context.Context, wishlistID string, userID string, role string) error {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return ports.ErrNotFound
	}
	found := false
	for i, member := range wishlist.Members {
		if member.UserID == userID {
			wishlist.Members[i].Role = role
			found = true
			break
		}
	}
	if !found {
		return ports.ErrNotFound
	}
	r.wishlists[wishlistID] = wishlist
	return nil
}

func (r *fakeRepository) AddMember(_ context.Context, wishlistID string, userID string, role string) error {
	wishlist, ok := r.wishlists[wishlistID]
	if !ok {
		return ports.ErrNotFound
	}

	wishlist.Members = append(wishlist.Members, domain.WishlistMember{
		WishlistID: wishlistID,
		UserID:     userID,
		Email:      "viewer@example.com",
		FullName:   "Viewer",
		Role:       role,
		CreatedAt:  fixedTime,
		UpdatedAt:  fixedTime,
	})
	r.wishlists[wishlistID] = wishlist
	return nil
}

func wishlistWithItems(ownerID string, items []domain.WishlistItem) domain.Wishlist {
	return domain.Wishlist{
		ID:          wishlistID1,
		OwnerID:     ownerID,
		Title:       "Weekend Hosting",
		Description: "Plates and candles",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
		Items:       items,
	}
}

func cloneWishlist(wishlist domain.Wishlist) domain.Wishlist {
	cloned := wishlist
	cloned.Members = append([]domain.WishlistMember{}, wishlist.Members...)
	cloned.Invites = make([]domain.WishlistInvite, 0, len(wishlist.Invites))
	for _, invite := range wishlist.Invites {
		cloned.Invites = append(cloned.Invites, cloneInvite(invite))
	}
	cloned.Items = make([]domain.WishlistItem, 0, len(wishlist.Items))
	for _, item := range wishlist.Items {
		cloned.Items = append(cloned.Items, cloneItem(item))
	}

	return cloned
}

func cloneInvite(invite domain.WishlistInvite) domain.WishlistInvite {
	cloned := invite
	if invite.InvitedByUserID != nil {
		invitedBy := *invite.InvitedByUserID
		cloned.InvitedByUserID = &invitedBy
	}
	cloned.AcceptedAt = cloneTime(invite.AcceptedAt)
	return cloned
}

func cloneItem(item domain.WishlistItem) domain.WishlistItem {
	cloned := item
	cloned.Notes = cloneString(item.Notes)
	cloned.PriceLabel = cloneString(item.PriceLabel)
	cloned.ImageURL = cloneString(item.ImageURL)
	cloned.ProductURL = cloneString(item.ProductURL)
	cloned.PurchasedAt = cloneTime(item.PurchasedAt)
	return cloned
}

func userContext(userID string, email string) context.Context {
	return authctx.WithUser(context.Background(), authctx.User{
		ID:    userID,
		Email: email,
	})
}
