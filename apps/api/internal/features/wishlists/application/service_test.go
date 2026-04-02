package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/ports"
)

func TestServicePatchWishlistPreservesOmittedFieldsAndClearsNullableValues(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	cover := "https://example.com/original.jpg"
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:            wishlistID1,
		Title:         "Original",
		Description:   "Warm lighting",
		Year:          2026,
		CoverImageURL: &cover,
		CreatedAt:     fixedTime,
		UpdatedAt:     fixedTime,
		Items:         []domain.WishlistItem{},
	}

	service := NewService(repo)

	wishlist, err := service.Patch(context.Background(), wishlistID1, &PatchWishlistInput{
		Title:         PatchField[string]{Set: true, Value: "  Updated Title  "},
		CoverImageURL: PatchField[*string]{Set: true, Value: nil},
		IsShared:      PatchField[bool]{Set: true, Value: true},
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
	if !wishlist.IsShared {
		t.Fatalf("expected wishlist to be shared")
	}
}

func TestServicePatchItemPurchasedStatusRefreshesPurchasedAt(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:          wishlistID1,
		Title:       "Weekend Hosting",
		Description: "Plates and candles",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
		Items: []domain.WishlistItem{
			{
				ID:        itemID1,
				Title:     "Stoneware plates",
				Rank:      1,
				Priority:  domain.ItemPriorityMedium,
				Status:    domain.ItemStatusSaved,
				CreatedAt: fixedTime,
				UpdatedAt: fixedTime,
			},
		},
	}

	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime.Add(24 * time.Hour) }

	item, err := service.PatchItem(context.Background(), wishlistID1, itemID1, &PatchItemInput{
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

	item, err = service.PatchItem(context.Background(), wishlistID1, itemID1, &PatchItemInput{
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
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:          wishlistID1,
		Title:       "Weekend Hosting",
		Description: "Plates and candles",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
		Items: []domain.WishlistItem{
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
		},
	}

	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime.Add(24 * time.Hour) }

	item, err := service.PatchItem(context.Background(), wishlistID1, itemID1, &PatchItemInput{
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

func TestServicePatchItemPreservesPurchasedAtForUnrelatedPurchasedEdit(t *testing.T) {
	t.Parallel()
	originalPurchasedAt := fixedTime.Add(-12 * time.Hour)
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:          wishlistID1,
		Title:       "Weekend Hosting",
		Description: "Plates and candles",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
		Items: []domain.WishlistItem{
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
		},
	}

	service := NewService(repo)
	service.nowFn = func() time.Time { return fixedTime.Add(24 * time.Hour) }

	item, err := service.PatchItem(context.Background(), wishlistID1, itemID1, &PatchItemInput{
		Title: PatchField[string]{Set: true, Value: "Updated plates"},
	})
	if err != nil {
		t.Fatalf("PatchItem returned error: %v", err)
	}
	if item.Title != "Updated plates" {
		t.Fatalf("expected title to update, got %q", item.Title)
	}
	if item.PurchasedAt == nil {
		t.Fatalf("expected purchasedAt to remain set")
	}
	if !item.PurchasedAt.Equal(originalPurchasedAt) {
		t.Fatalf("expected purchasedAt to stay %v, got %v", originalPurchasedAt, *item.PurchasedAt)
	}
}

func TestServiceReorderItemsUsesFlutterSubsetOrderingRules(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:          wishlistID1,
		Title:       "Desk Setup",
		Description: "Work tools",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
		Items: []domain.WishlistItem{
			{ID: itemID1, Title: "Lamp", Rank: 1, Priority: domain.ItemPriorityMedium, Status: domain.ItemStatusSaved, CreatedAt: fixedTime, UpdatedAt: fixedTime},
			{ID: itemID2, Title: "Monitor", Rank: 2, Priority: domain.ItemPriorityMedium, Status: domain.ItemStatusSaved, CreatedAt: fixedTime, UpdatedAt: fixedTime},
			{ID: itemID3, Title: "Keyboard", Rank: 3, Priority: domain.ItemPriorityMedium, Status: domain.ItemStatusSaved, CreatedAt: fixedTime, UpdatedAt: fixedTime},
		},
	}

	service := NewService(repo)

	wishlist, err := service.ReorderItems(context.Background(), wishlistID1, []string{itemID3, "not-a-real-item", itemID3, itemID1})
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

func TestServicePatchItemReturnsItemNotFound(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:          wishlistID1,
		Title:       "Travel",
		Description: "Carry on",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime,
		Items:       []domain.WishlistItem{},
	}

	service := NewService(repo)

	_, err := service.PatchItem(context.Background(), wishlistID1, itemID1, &PatchItemInput{
		Title: PatchField[string]{Set: true, Value: "Bag"},
	})
	if err == nil {
		t.Fatalf("expected PatchItem to return an error")
	}

	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeItemNotFound {
		t.Fatalf("expected item not found error, got %s", appErr.Code)
	}
}

func TestServiceCreateValidatesYear(t *testing.T) {
	t.Parallel()
	service := NewService(newFakeRepository())

	_, err := service.Create(context.Background(), &CreateWishlistInput{
		Title: "Reading Corner",
		Year:  1999,
	})
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeValidation || appErr.Field != "year" {
		t.Fatalf("expected year validation error, got %+v", appErr)
	}
}

func TestServiceCreateRejectsNilInput(t *testing.T) {
	t.Parallel()
	service := NewService(newFakeRepository())

	_, err := service.Create(context.Background(), nil)
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeValidation || appErr.Field != "input" {
		t.Fatalf("expected input validation error, got %+v", appErr)
	}
}

func TestServicePatchRejectsNilInput(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		Title:     "Travel",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
	}

	service := NewService(repo)

	_, err := service.Patch(context.Background(), wishlistID1, nil)
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeValidation || appErr.Field != "input" {
		t.Fatalf("expected input validation error, got %+v", appErr)
	}
}

func TestServiceAddItemRejectsNilInput(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		Title:     "Travel",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Items:     []domain.WishlistItem{},
	}

	service := NewService(repo)

	_, err := service.AddItem(context.Background(), wishlistID1, nil)
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeValidation || appErr.Field != "input" {
		t.Fatalf("expected input validation error, got %+v", appErr)
	}
}

func TestServicePatchItemRejectsNilInput(t *testing.T) {
	t.Parallel()
	repo := newFakeRepository()
	repo.wishlists[wishlistID1] = domain.Wishlist{
		ID:        wishlistID1,
		Title:     "Travel",
		Year:      2026,
		CreatedAt: fixedTime,
		UpdatedAt: fixedTime,
		Items: []domain.WishlistItem{
			{
				ID:        itemID1,
				Title:     "Bag",
				Rank:      1,
				Priority:  domain.ItemPriorityMedium,
				Status:    domain.ItemStatusSaved,
				CreatedAt: fixedTime,
				UpdatedAt: fixedTime,
			},
		},
	}

	service := NewService(repo)

	_, err := service.PatchItem(context.Background(), wishlistID1, itemID1, nil)
	if err == nil {
		t.Fatalf("expected validation error")
	}

	appErr, ok := AsError(err)
	if !ok {
		t.Fatalf("expected application error, got %T", err)
	}
	if appErr.Code != ErrorCodeValidation || appErr.Field != "input" {
		t.Fatalf("expected input validation error, got %+v", appErr)
	}
}

const (
	wishlistID1 = "11111111-1111-1111-1111-111111111111"
	itemID1     = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	itemID2     = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
	itemID3     = "cccccccc-cccc-cccc-cccc-cccccccccccc"
)

var fixedTime = time.Date(2026, 3, 29, 12, 0, 0, 0, time.UTC)

type fakeRepository struct {
	wishlists map[string]domain.Wishlist
}

func newFakeRepository() *fakeRepository {
	return &fakeRepository{
		wishlists: map[string]domain.Wishlist{},
	}
}

func (r *fakeRepository) List(context.Context) ([]domain.Wishlist, error) {
	result := make([]domain.Wishlist, 0, len(r.wishlists))
	for _, wishlist := range r.wishlists {
		result = append(result, cloneWishlist(wishlist))
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
		Title:         params.Title,
		Description:   params.Description,
		Year:          params.Year,
		CoverImageURL: cloneString(params.CoverImageURL),
		IsShared:      params.IsShared,
		CreatedAt:     fixedTime,
		UpdatedAt:     fixedTime,
		SharedUsers:   []domain.SharedUser{},
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
	wishlist.IsShared = params.IsShared
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

	nextItems := make([]domain.WishlistItem, 0, len(orderedItemIDs))
	for index, itemID := range orderedItemIDs {
		item, ok := itemByID[itemID]
		if !ok {
			continue
		}

		item.Rank = index + 1
		nextItems = append(nextItems, item)
	}

	if len(nextItems) != len(wishlist.Items) {
		return errors.New("reorder expected full item list")
	}

	wishlist.Items = nextItems
	r.wishlists[wishlistID] = wishlist
	return nil
}

func cloneWishlist(wishlist domain.Wishlist) domain.Wishlist {
	cloned := wishlist
	cloned.SharedUsers = append([]domain.SharedUser{}, wishlist.SharedUsers...)
	cloned.Items = make([]domain.WishlistItem, 0, len(wishlist.Items))
	for _, item := range wishlist.Items {
		cloned.Items = append(cloned.Items, cloneItem(item))
	}

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
