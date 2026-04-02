package wishlisthttp

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
)

func TestPatchWishlistExplicitNullPreservesPatchSemantics(t *testing.T) {
	t.Parallel()
	service := &stubService{
		patchWishlist: func(_ context.Context, id string, input *application.PatchWishlistInput) (domain.Wishlist, error) {
			if id != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, id)
			}
			if input == nil {
				t.Fatalf("expected input to be non-nil")
			}
			if !input.CoverImageURL.Set {
				t.Fatalf("expected coverImageUrl patch field to be marked as set")
			}
			if input.CoverImageURL.Value != nil {
				t.Fatalf("expected explicit null coverImageUrl to decode as nil, got %v", *input.CoverImageURL.Value)
			}

			return sampleWishlist(), nil
		},
	}

	response := performRequest(t, service, http.MethodPatch, "/wishlists/"+wishlistID, `{"coverImageUrl":null}`)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestGetWishlistNotFoundReturns404(t *testing.T) {
	t.Parallel()
	service := &stubService{
		getWishlist: func(context.Context, string) (domain.Wishlist, error) {
			return domain.Wishlist{}, application.WishlistNotFound()
		},
	}

	response := performRequest(t, service, http.MethodGet, "/wishlists/"+wishlistID, "")
	if response.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", response.Code)
	}

	var payload map[string]map[string]string
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["error"]["code"] != string(application.ErrorCodeWishlistNotFound) {
		t.Fatalf("expected wishlist not found code, got %q", payload["error"]["code"])
	}
}

func TestCreateWishlistValidationReturns400(t *testing.T) {
	t.Parallel()
	service := &stubService{
		createWishlist: func(context.Context, *application.CreateWishlistInput) (domain.Wishlist, error) {
			return domain.Wishlist{}, application.ValidationError("title", "title is required")
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists", `{"title":"","description":"","year":2026}`)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", response.Code)
	}

	var payload struct {
		Error struct {
			Code  string `json:"code"`
			Field string `json:"field"`
		} `json:"error"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Error.Code != string(application.ErrorCodeValidation) || payload.Error.Field != "title" {
		t.Fatalf("unexpected error payload: %+v", payload)
	}
}

func TestListWishlistsReturnsAggregateJSON(t *testing.T) {
	t.Parallel()
	service := &stubService{
		listWishlists: func(context.Context) ([]domain.Wishlist, error) {
			return []domain.Wishlist{sampleWishlist()}, nil
		},
	}

	response := performRequest(t, service, http.MethodGet, "/wishlists", "")
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", response.Code)
	}

	var payload []map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(payload) != 1 {
		t.Fatalf("expected one wishlist, got %d", len(payload))
	}
	if _, ok := payload[0]["sharedUsers"].([]any); !ok {
		t.Fatalf("expected sharedUsers to be an array, got %#v", payload[0]["sharedUsers"])
	}
}

func TestCreateWishlistReturnsCreatedJSONAndPassesInput(t *testing.T) {
	t.Parallel()
	coverImageURL := "https://example.com/cover.jpg"
	service := &stubService{
		createWishlist: func(_ context.Context, input *application.CreateWishlistInput) (domain.Wishlist, error) {
			if input == nil {
				t.Fatalf("expected input to be non-nil")
			}
			if input.Title != "Weekend Hosting" {
				t.Fatalf("expected title to be passed through, got %q", input.Title)
			}
			if input.Description != "Plates and flowers" {
				t.Fatalf("expected description to be passed through, got %q", input.Description)
			}
			if input.Year != 2026 {
				t.Fatalf("expected year 2026, got %d", input.Year)
			}
			if input.CoverImageURL == nil || *input.CoverImageURL != coverImageURL {
				t.Fatalf("expected cover image url %q, got %#v", coverImageURL, input.CoverImageURL)
			}
			if !input.IsShared {
				t.Fatalf("expected shared wishlist flag to be true")
			}

			wishlist := sampleWishlist()
			wishlist.CoverImageURL = &coverImageURL
			wishlist.IsShared = true
			return wishlist, nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists", `{"title":"Weekend Hosting","description":"Plates and flowers","year":2026,"coverImageUrl":"https://example.com/cover.jpg","isShared":true}`)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["title"] != "Weekend Hosting" {
		t.Fatalf("expected response title to match created wishlist, got %#v", payload["title"])
	}
}

func TestGetWishlistReturnsAggregateJSON(t *testing.T) {
	t.Parallel()
	service := &stubService{
		getWishlist: func(_ context.Context, id string) (domain.Wishlist, error) {
			if id != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, id)
			}
			return sampleWishlist(), nil
		},
	}

	response := performRequest(t, service, http.MethodGet, "/wishlists/"+wishlistID, "")
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["id"] != wishlistID {
		t.Fatalf("expected wishlist id %s, got %#v", wishlistID, payload["id"])
	}
}

func TestDeleteWishlistReturnsNoContent(t *testing.T) {
	t.Parallel()
	service := &stubService{
		deleteWishlist: func(_ context.Context, id string) error {
			if id != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, id)
			}
			return nil
		},
	}

	response := performRequest(t, service, http.MethodDelete, "/wishlists/"+wishlistID, "")
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d with body %s", response.Code, response.Body.String())
	}
	if response.Body.Len() != 0 {
		t.Fatalf("expected empty body, got %q", response.Body.String())
	}
}

func TestArchiveWishlistReturnsUpdatedWishlist(t *testing.T) {
	t.Parallel()
	service := &stubService{
		archive: func(_ context.Context, id string) (domain.Wishlist, error) {
			if id != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, id)
			}
			wishlist := sampleWishlist()
			wishlist.IsArchived = true
			return wishlist, nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/archive", "")
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["isArchived"] != true {
		t.Fatalf("expected archived wishlist response, got %#v", payload["isArchived"])
	}
}

func TestRestoreWishlistReturnsUpdatedWishlist(t *testing.T) {
	t.Parallel()
	service := &stubService{
		restore: func(_ context.Context, id string) (domain.Wishlist, error) {
			if id != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, id)
			}
			wishlist := sampleWishlist()
			wishlist.IsArchived = false
			return wishlist, nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/restore", "")
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["isArchived"] != false {
		t.Fatalf("expected restored wishlist response, got %#v", payload["isArchived"])
	}
}

func TestAddItemReturnsCreatedJSONAndPassesInput(t *testing.T) {
	t.Parallel()
	notes := "Set of six"
	productURL := "https://example.com/plates"
	service := &stubService{
		addItem: func(_ context.Context, gotWishlistID string, input *application.AddItemInput) (domain.WishlistItem, error) {
			if gotWishlistID != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, gotWishlistID)
			}
			if input == nil {
				t.Fatalf("expected input to be non-nil")
			}
			if input.Title != "Stoneware plates" {
				t.Fatalf("expected title to be passed through, got %q", input.Title)
			}
			if input.Notes == nil || *input.Notes != notes {
				t.Fatalf("expected notes %q, got %#v", notes, input.Notes)
			}
			if input.ProductURL == nil || *input.ProductURL != productURL {
				t.Fatalf("expected product url %q, got %#v", productURL, input.ProductURL)
			}
			if input.Priority != domain.ItemPriorityHigh {
				t.Fatalf("expected priority %q, got %q", domain.ItemPriorityHigh, input.Priority)
			}
			if input.Status != domain.ItemStatusSaved {
				t.Fatalf("expected status %q, got %q", domain.ItemStatusSaved, input.Status)
			}

			item := sampleWishlist().Items[0]
			item.Notes = &notes
			item.ProductURL = &productURL
			return item, nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/items", `{"title":"Stoneware plates","notes":"Set of six","priority":"High","status":"Saved","productUrl":"https://example.com/plates"}`)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["id"] != itemID {
		t.Fatalf("expected item id %s, got %#v", itemID, payload["id"])
	}
}

func TestPatchItemExplicitNullPreservesPatchSemantics(t *testing.T) {
	t.Parallel()
	service := &stubService{
		patchItem: func(_ context.Context, gotWishlistID string, gotItemID string, input *application.PatchItemInput) (domain.WishlistItem, error) {
			if gotWishlistID != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, gotWishlistID)
			}
			if gotItemID != itemID {
				t.Fatalf("expected item id %s, got %s", itemID, gotItemID)
			}
			if input == nil {
				t.Fatalf("expected input to be non-nil")
			}
			if !input.Notes.Set {
				t.Fatalf("expected notes patch field to be marked as set")
			}
			if input.Notes.Value != nil {
				t.Fatalf("expected explicit null notes to decode as nil, got %#v", input.Notes.Value)
			}

			return sampleWishlist().Items[0], nil
		},
	}

	response := performRequest(t, service, http.MethodPatch, "/wishlists/"+wishlistID+"/items/"+itemID, `{"notes":null}`)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestDeleteItemReturnsNoContent(t *testing.T) {
	t.Parallel()
	service := &stubService{
		deleteItem: func(_ context.Context, gotWishlistID string, gotItemID string) error {
			if gotWishlistID != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, gotWishlistID)
			}
			if gotItemID != itemID {
				t.Fatalf("expected item id %s, got %s", itemID, gotItemID)
			}
			return nil
		},
	}

	response := performRequest(t, service, http.MethodDelete, "/wishlists/"+wishlistID+"/items/"+itemID, "")
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestReorderItemsReturnsUpdatedWishlistAndPassesOrder(t *testing.T) {
	t.Parallel()
	orderedItemIDs := []string{itemID, "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}
	service := &stubService{
		reorderItems: func(_ context.Context, gotWishlistID string, gotOrderedItemIDs []string) (domain.Wishlist, error) {
			if gotWishlistID != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, gotWishlistID)
			}
			if len(gotOrderedItemIDs) != len(orderedItemIDs) {
				t.Fatalf("expected %d ordered item ids, got %d", len(orderedItemIDs), len(gotOrderedItemIDs))
			}
			for index, itemID := range orderedItemIDs {
				if gotOrderedItemIDs[index] != itemID {
					t.Fatalf("expected ordered item id %q at index %d, got %q", itemID, index, gotOrderedItemIDs[index])
				}
			}

			return sampleWishlist(), nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/items/reorder", `{"orderedItemIds":["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"]}`)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["id"] != wishlistID {
		t.Fatalf("expected wishlist id %s, got %#v", wishlistID, payload["id"])
	}
}

func TestWishlistRoutesReturnInternalServerErrorForUnexpectedErrors(t *testing.T) {
	t.Parallel()
	service := &stubService{
		listWishlists: func(context.Context) ([]domain.Wishlist, error) {
			return nil, errors.New("database offline")
		},
	}

	response := performRequest(t, service, http.MethodGet, "/wishlists", "")
	if response.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d with body %s", response.Code, response.Body.String())
	}

	var payload struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Error.Code != "internal_error" {
		t.Fatalf("expected internal error code, got %q", payload.Error.Code)
	}
	if payload.Error.Message != "internal server error" {
		t.Fatalf("expected generic internal error message, got %q", payload.Error.Message)
	}
}

func performRequest(t *testing.T, service Service, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()

	mux := http.NewServeMux()
	RegisterRoutes(mux, slog.New(slog.NewTextHandler(io.Discard, nil)), service)

	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}

	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	return recorder
}

func sampleWishlist() domain.Wishlist {
	return domain.Wishlist{
		ID:          wishlistID,
		Title:       "Weekend Hosting",
		Description: "Plates and flowers",
		Year:        2026,
		CreatedAt:   time.Date(2026, 3, 29, 10, 0, 0, 0, time.UTC),
		UpdatedAt:   time.Date(2026, 3, 29, 11, 0, 0, 0, time.UTC),
		SharedUsers: []domain.SharedUser{},
		Items: []domain.WishlistItem{
			{
				ID:        itemID,
				Title:     "Stoneware plates",
				Rank:      1,
				Priority:  domain.ItemPriorityHigh,
				Status:    domain.ItemStatusSaved,
				CreatedAt: time.Date(2026, 3, 28, 10, 0, 0, 0, time.UTC),
				UpdatedAt: time.Date(2026, 3, 29, 11, 0, 0, 0, time.UTC),
			},
		},
	}
}

const (
	wishlistID = "11111111-1111-1111-1111-111111111111"
	itemID     = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
)

type stubService struct {
	listWishlists  func(context.Context) ([]domain.Wishlist, error)
	getWishlist    func(context.Context, string) (domain.Wishlist, error)
	createWishlist func(context.Context, *application.CreateWishlistInput) (domain.Wishlist, error)
	patchWishlist  func(context.Context, string, *application.PatchWishlistInput) (domain.Wishlist, error)
	deleteWishlist func(context.Context, string) error
	archive        func(context.Context, string) (domain.Wishlist, error)
	restore        func(context.Context, string) (domain.Wishlist, error)
	addItem        func(context.Context, string, *application.AddItemInput) (domain.WishlistItem, error)
	patchItem      func(context.Context, string, string, *application.PatchItemInput) (domain.WishlistItem, error)
	deleteItem     func(context.Context, string, string) error
	reorderItems   func(context.Context, string, []string) (domain.Wishlist, error)
}

func (s *stubService) List(ctx context.Context) ([]domain.Wishlist, error) {
	if s.listWishlists == nil {
		return []domain.Wishlist{}, nil
	}
	return s.listWishlists(ctx)
}

func (s *stubService) GetByID(ctx context.Context, id string) (domain.Wishlist, error) {
	if s.getWishlist == nil {
		return domain.Wishlist{}, nil
	}
	return s.getWishlist(ctx, id)
}

func (s *stubService) Create(ctx context.Context, input *application.CreateWishlistInput) (domain.Wishlist, error) {
	if s.createWishlist == nil {
		return domain.Wishlist{}, nil
	}
	return s.createWishlist(ctx, input)
}

func (s *stubService) Patch(ctx context.Context, id string, input *application.PatchWishlistInput) (domain.Wishlist, error) {
	if s.patchWishlist == nil {
		return domain.Wishlist{}, nil
	}
	return s.patchWishlist(ctx, id, input)
}

func (s *stubService) Delete(ctx context.Context, id string) error {
	if s.deleteWishlist == nil {
		return nil
	}
	return s.deleteWishlist(ctx, id)
}

func (s *stubService) Archive(ctx context.Context, id string) (domain.Wishlist, error) {
	if s.archive == nil {
		return domain.Wishlist{}, nil
	}
	return s.archive(ctx, id)
}

func (s *stubService) Restore(ctx context.Context, id string) (domain.Wishlist, error) {
	if s.restore == nil {
		return domain.Wishlist{}, nil
	}
	return s.restore(ctx, id)
}

func (s *stubService) AddItem(ctx context.Context, wishlistID string, input *application.AddItemInput) (domain.WishlistItem, error) {
	if s.addItem == nil {
		return domain.WishlistItem{}, nil
	}
	return s.addItem(ctx, wishlistID, input)
}

func (s *stubService) PatchItem(ctx context.Context, wishlistID, itemID string, input *application.PatchItemInput) (domain.WishlistItem, error) {
	if s.patchItem == nil {
		return domain.WishlistItem{}, nil
	}
	return s.patchItem(ctx, wishlistID, itemID, input)
}

func (s *stubService) DeleteItem(ctx context.Context, wishlistID, itemID string) error {
	if s.deleteItem == nil {
		return nil
	}
	return s.deleteItem(ctx, wishlistID, itemID)
}

func (s *stubService) ReorderItems(ctx context.Context, wishlistID string, orderedItemIDs []string) (domain.Wishlist, error) {
	if s.reorderItems == nil {
		return domain.Wishlist{}, nil
	}
	return s.reorderItems(ctx, wishlistID, orderedItemIDs)
}
