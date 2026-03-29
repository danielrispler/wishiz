package wishlisthttp

import (
	"bytes"
	"context"
	"encoding/json"
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
	service := &stubService{
		patchWishlist: func(_ context.Context, id string, input application.PatchWishlistInput) (domain.Wishlist, error) {
			if id != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, id)
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
	service := &stubService{
		createWishlist: func(context.Context, application.CreateWishlistInput) (domain.Wishlist, error) {
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

func performRequest(t *testing.T, service Service, method string, path string, body string) *httptest.ResponseRecorder {
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
	createWishlist func(context.Context, application.CreateWishlistInput) (domain.Wishlist, error)
	patchWishlist  func(context.Context, string, application.PatchWishlistInput) (domain.Wishlist, error)
	deleteWishlist func(context.Context, string) error
	archive        func(context.Context, string) (domain.Wishlist, error)
	restore        func(context.Context, string) (domain.Wishlist, error)
	addItem        func(context.Context, string, application.AddItemInput) (domain.WishlistItem, error)
	patchItem      func(context.Context, string, string, application.PatchItemInput) (domain.WishlistItem, error)
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

func (s *stubService) Create(ctx context.Context, input application.CreateWishlistInput) (domain.Wishlist, error) {
	if s.createWishlist == nil {
		return domain.Wishlist{}, nil
	}
	return s.createWishlist(ctx, input)
}

func (s *stubService) Patch(ctx context.Context, id string, input application.PatchWishlistInput) (domain.Wishlist, error) {
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

func (s *stubService) AddItem(ctx context.Context, wishlistID string, input application.AddItemInput) (domain.WishlistItem, error) {
	if s.addItem == nil {
		return domain.WishlistItem{}, nil
	}
	return s.addItem(ctx, wishlistID, input)
}

func (s *stubService) PatchItem(ctx context.Context, wishlistID string, itemID string, input application.PatchItemInput) (domain.WishlistItem, error) {
	if s.patchItem == nil {
		return domain.WishlistItem{}, nil
	}
	return s.patchItem(ctx, wishlistID, itemID, input)
}

func (s *stubService) DeleteItem(ctx context.Context, wishlistID string, itemID string) error {
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
