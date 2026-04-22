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
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
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

func TestListWishlistsReturnsMembersAndInvitesJSON(t *testing.T) {
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
	if _, ok := payload[0]["members"].([]any); !ok {
		t.Fatalf("expected members to be an array, got %#v", payload[0]["members"])
	}
	if _, ok := payload[0]["invites"].([]any); !ok {
		t.Fatalf("expected invites to be an array, got %#v", payload[0]["invites"])
	}
	if _, exists := payload[0]["sharedUsers"]; exists {
		t.Fatalf("did not expect old sharedUsers field")
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

			wishlist := sampleWishlist()
			wishlist.CoverImageURL = &coverImageURL
			return wishlist, nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists", `{"title":"Weekend Hosting","description":"Plates and flowers","year":2026,"coverImageUrl":"https://example.com/cover.jpg"}`)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestAddItemReturnsCreatedJSONAndPassesLowercaseInput(t *testing.T) {
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

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/items", `{"title":"Stoneware plates","notes":"Set of six","priority":"high","status":"saved","productUrl":"https://example.com/plates"}`)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestJoinWishlistPassesInviteToken(t *testing.T) {
	t.Parallel()
	service := &stubService{
		join: func(_ context.Context, gotWishlistID string, input *application.JoinWishlistInput) (domain.Wishlist, error) {
			if gotWishlistID != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, gotWishlistID)
			}
			if input == nil || input.Token != "raw-token" {
				t.Fatalf("expected invite token to pass through, got %#v", input)
			}
			return sampleWishlist(), nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/join", `{"token":"raw-token"}`)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestCreateInviteReturnsCreatedInvite(t *testing.T) {
	t.Parallel()
	service := &stubService{
		createInvite: func(_ context.Context, gotWishlistID string, input *application.CreateInviteInput) (domain.WishlistInvite, error) {
			if gotWishlistID != wishlistID {
				t.Fatalf("expected wishlist id %s, got %s", wishlistID, gotWishlistID)
			}
			if input == nil || input.Email != "viewer@example.com" || input.Role != domain.MemberRoleEditor {
				t.Fatalf("unexpected invite input: %#v", input)
			}
			return domain.WishlistInvite{
				ID:         inviteID,
				WishlistID: wishlistID,
				Email:      "viewer@example.com",
				Role:       domain.MemberRoleEditor,
				ExpiresAt:  fixedTime.Add(24 * time.Hour),
				CreatedAt:  fixedTime,
				UpdatedAt:  fixedTime,
				Token:      "raw-token",
			}, nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/wishlists/"+wishlistID+"/invites", `{"email":"viewer@example.com","role":"editor"}`)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}

	var payload map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload["token"] != "raw-token" {
		t.Fatalf("expected invite token in create response, got %#v", payload["token"])
	}
}

func TestDeleteInviteAndMemberReturnNoContent(t *testing.T) {
	t.Parallel()
	service := &stubService{
		deleteInvite: func(_ context.Context, gotWishlistID string, gotInviteID string) error {
			if gotWishlistID != wishlistID || gotInviteID != inviteID {
				t.Fatalf("unexpected delete invite ids: %s %s", gotWishlistID, gotInviteID)
			}
			return nil
		},
		removeMember: func(_ context.Context, gotWishlistID string, gotUserID string) error {
			if gotWishlistID != wishlistID || gotUserID != memberID {
				t.Fatalf("unexpected remove member ids: %s %s", gotWishlistID, gotUserID)
			}
			return nil
		},
	}

	response := performRequest(t, service, http.MethodDelete, "/wishlists/"+wishlistID+"/invites/"+inviteID, "")
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected invite delete 204, got %d", response.Code)
	}

	response = performRequest(t, service, http.MethodDelete, "/wishlists/"+wishlistID+"/members/"+memberID, "")
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected member delete 204, got %d", response.Code)
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
}

func performRequest(t *testing.T, service Service, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()

	mux := http.NewServeMux()
	RegisterRoutes(mux, slog.New(slog.NewTextHandler(io.Discard, nil)), service, func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			ctx := authctx.WithUser(r.Context(), authctx.User{
				ID:    ownerID,
				Email: "owner@example.com",
			})
			next(w, r.WithContext(ctx))
		}
	})

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
		OwnerID:     ownerID,
		Title:       "Weekend Hosting",
		Description: "Plates and flowers",
		Year:        2026,
		CreatedAt:   fixedTime,
		UpdatedAt:   fixedTime.Add(time.Hour),
		Members: []domain.WishlistMember{
			{
				WishlistID: wishlistID,
				UserID:     memberID,
				Email:      "viewer@example.com",
				FullName:   "Viewer",
				Role:       domain.MemberRoleViewer,
				CreatedAt:  fixedTime,
				UpdatedAt:  fixedTime,
			},
		},
		Invites: []domain.WishlistInvite{
			{
				ID:         inviteID,
				WishlistID: wishlistID,
				Email:      "pending@example.com",
				Role:       domain.MemberRoleViewer,
				ExpiresAt:  fixedTime.Add(24 * time.Hour),
				CreatedAt:  fixedTime,
				UpdatedAt:  fixedTime,
			},
		},
		Items: []domain.WishlistItem{
			{
				ID:        itemID,
				Title:     "Stoneware plates",
				Rank:      1,
				Priority:  domain.ItemPriorityHigh,
				Status:    domain.ItemStatusSaved,
				CreatedAt: fixedTime,
				UpdatedAt: fixedTime.Add(time.Hour),
			},
		},
	}
}

const (
	ownerID    = "11111111-1111-1111-1111-111111111111"
	memberID   = "22222222-2222-2222-2222-222222222222"
	wishlistID = "33333333-3333-3333-3333-333333333333"
	itemID     = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	inviteID   = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
)

var fixedTime = time.Date(2026, 3, 29, 10, 0, 0, 0, time.UTC)

type stubService struct {
	createInvite   func(context.Context, string, *application.CreateInviteInput) (domain.WishlistInvite, error)
	deleteInvite   func(context.Context, string, string) error
	removeMember   func(context.Context, string, string) error
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
	join           func(context.Context, string, *application.JoinWishlistInput) (domain.Wishlist, error)
	updateMemberRole func(context.Context, string, string, *application.PatchWishlistMemberInput) error
}

func (s *stubService) CreateInvite(ctx context.Context, wishlistID string, input *application.CreateInviteInput) (domain.WishlistInvite, error) {
	if s.createInvite == nil {
		return domain.WishlistInvite{}, nil
	}
	return s.createInvite(ctx, wishlistID, input)
}

func (s *stubService) DeleteInvite(ctx context.Context, wishlistID string, inviteID string) error {
	if s.deleteInvite == nil {
		return nil
	}
	return s.deleteInvite(ctx, wishlistID, inviteID)
}

func (s *stubService) RemoveMember(ctx context.Context, wishlistID string, userID string) error {
	if s.removeMember == nil {
		return nil
	}
	return s.removeMember(ctx, wishlistID, userID)
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

func (s *stubService) Join(ctx context.Context, id string, input *application.JoinWishlistInput) (domain.Wishlist, error) {
	if s.join == nil {
		return domain.Wishlist{}, nil
	}
	return s.join(ctx, id, input)
}

func (s *stubService) UpdateMemberRole(ctx context.Context, wishlistID string, userID string, input *application.PatchWishlistMemberInput) error {
	if s.updateMemberRole == nil {
		return nil
	}
	return s.updateMemberRole(ctx, wishlistID, userID, input)
}
