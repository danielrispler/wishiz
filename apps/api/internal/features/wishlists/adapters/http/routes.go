package wishlisthttp

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

type Service interface {
	AddSharedUser(ctx context.Context, wishlistID string, input *application.AddSharedUserInput) error
	RemoveSharedUser(ctx context.Context, wishlistID string, userID string) error
	List(ctx context.Context) ([]domain.Wishlist, error)
	GetByID(ctx context.Context, id string) (domain.Wishlist, error)
	Create(ctx context.Context, input *application.CreateWishlistInput) (domain.Wishlist, error)
	Patch(ctx context.Context, id string, input *application.PatchWishlistInput) (domain.Wishlist, error)
	Delete(ctx context.Context, id string) error
	Archive(ctx context.Context, id string) (domain.Wishlist, error)
	Restore(ctx context.Context, id string) (domain.Wishlist, error)
	AddItem(ctx context.Context, wishlistID string, input *application.AddItemInput) (domain.WishlistItem, error)
	PatchItem(ctx context.Context, wishlistID, itemID string, input *application.PatchItemInput) (domain.WishlistItem, error)
	DeleteItem(ctx context.Context, wishlistID string, itemID string) error
	ReorderItems(ctx context.Context, wishlistID string, orderedItemIDs []string) (domain.Wishlist, error)
	Join(ctx context.Context, id string) (domain.Wishlist, error)
}

type handler struct {
	logger  *slog.Logger
	service Service
}

type createWishlistRequest struct {
	Title         string  `json:"title"`
	Description   string  `json:"description"`
	Year          int     `json:"year"`
	CoverImageURL *string `json:"coverImageUrl"`
	IsShared      bool    `json:"isShared"`
}

type patchWishlistRequest struct {
	Title         application.PatchField[string]  `json:"title"`
	Description   application.PatchField[string]  `json:"description"`
	Year          application.PatchField[int]     `json:"year"`
	CoverImageURL application.PatchField[*string] `json:"coverImageUrl"`
	IsShared      application.PatchField[bool]    `json:"isShared"`
}

type createItemRequest struct {
	Title      string  `json:"title"`
	Notes      *string `json:"notes"`
	PriceLabel *string `json:"priceLabel"`
	Priority   string  `json:"priority"`
	Status     string  `json:"status"`
	ImageURL   *string `json:"imageUrl"`
	ProductURL *string `json:"productUrl"`
}

type patchItemRequest struct {
	Title      application.PatchField[string]  `json:"title"`
	Notes      application.PatchField[*string] `json:"notes"`
	PriceLabel application.PatchField[*string] `json:"priceLabel"`
	Priority   application.PatchField[string]  `json:"priority"`
	Status     application.PatchField[string]  `json:"status"`
	ImageURL   application.PatchField[*string] `json:"imageUrl"`
	ProductURL application.PatchField[*string] `json:"productUrl"`
}

type reorderItemsRequest struct {
	OrderedItemIDs []string `json:"orderedItemIds"`
}

type addSharedUserRequest struct {
	Name  string `json:"name"`
	Email string `json:"email"`
	Role  string `json:"role"`
}

type wishlistResponse struct {
	ID            string             `json:"id"`
	OwnerUserID   string             `json:"ownerUserId"`
	Title         string             `json:"title"`
	Description   string             `json:"description"`
	Year          int                `json:"year"`
	CoverImageURL *string            `json:"coverImageUrl"`
	CreatedAt     time.Time          `json:"createdAt"`
	UpdatedAt     time.Time          `json:"updatedAt"`
	IsArchived    bool               `json:"isArchived"`
	IsShared      bool               `json:"isShared"`
	SharedUsers   []sharedUserResult `json:"sharedUsers"`
	Items         []itemResponse     `json:"items"`
}

type sharedUserResult struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
	Role  string `json:"role"`
}

type itemResponse struct {
	ID          string     `json:"id"`
	Title       string     `json:"title"`
	Rank        int        `json:"rank"`
	Notes       *string    `json:"notes"`
	PriceLabel  *string    `json:"priceLabel"`
	Priority    string     `json:"priority"`
	Status      string     `json:"status"`
	ImageURL    *string    `json:"imageUrl"`
	ProductURL  *string    `json:"productUrl"`
	PurchasedAt *time.Time `json:"purchasedAt"`
	CreatedAt   time.Time  `json:"createdAt"`
	UpdatedAt   time.Time  `json:"updatedAt"`
}

type AuthMiddleware func(http.HandlerFunc) http.HandlerFunc

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, service Service, authMiddleware AuthMiddleware) {
	h := handler{
		logger:  logger,
		service: service,
	}

	if authMiddleware == nil {
		authMiddleware = func(next http.HandlerFunc) http.HandlerFunc {
			return next
		}
	}

	mux.HandleFunc("GET /wishlists", authMiddleware(withAuthenticatedUser(h.listWishlists)))
	mux.HandleFunc("POST /wishlists", authMiddleware(withAuthenticatedUser(h.createWishlist)))
	mux.HandleFunc("GET /wishlists/{id}", authMiddleware(withAuthenticatedUser(h.getWishlist)))
	mux.HandleFunc("PATCH /wishlists/{id}", authMiddleware(withAuthenticatedUser(h.patchWishlist)))
	mux.HandleFunc("DELETE /wishlists/{id}", authMiddleware(withAuthenticatedUser(h.deleteWishlist)))
	mux.HandleFunc("POST /wishlists/{id}/archive", authMiddleware(withAuthenticatedUser(h.archiveWishlist)))
	mux.HandleFunc("POST /wishlists/{id}/restore", authMiddleware(withAuthenticatedUser(h.restoreWishlist)))
	mux.HandleFunc("POST /wishlists/{id}/items", authMiddleware(withAuthenticatedUser(h.addItem)))
	mux.HandleFunc("PATCH /wishlists/{id}/items/{itemId}", authMiddleware(withAuthenticatedUser(h.patchItem)))
	mux.HandleFunc("DELETE /wishlists/{id}/items/{itemId}", authMiddleware(withAuthenticatedUser(h.deleteItem)))
	mux.HandleFunc("POST /wishlists/{id}/items/reorder", authMiddleware(withAuthenticatedUser(h.reorderItems)))
	mux.HandleFunc("POST /wishlists/{id}/shared-users", authMiddleware(withAuthenticatedUser(h.addSharedUser)))
	mux.HandleFunc("DELETE /wishlists/{id}/shared-users/{userId}", authMiddleware(withAuthenticatedUser(h.removeSharedUser)))
	mux.HandleFunc("POST /wishlists/{id}/join", authMiddleware(withAuthenticatedUser(h.joinWishlist)))
}

func withAuthenticatedUser(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authctx.UserFromContext(r.Context()); !ok {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
			return
		}
		h(w, r)
	}
}

func (h handler) listWishlists(w http.ResponseWriter, r *http.Request) {
	wishlists, err := h.service.List(r.Context())
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	response := make([]wishlistResponse, 0, len(wishlists))
	for _, wishlist := range wishlists {
		response = append(response, mapWishlistResponse(wishlist))
	}

	httpx.WriteJSON(w, http.StatusOK, response)
}

func (h handler) createWishlist(w http.ResponseWriter, r *http.Request) {
	var request createWishlistRequest
	if err := httpx.DecodeJSON(r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.Create(r.Context(), &application.CreateWishlistInput{
		Title:         request.Title,
		Description:   request.Description,
		Year:          request.Year,
		CoverImageURL: request.CoverImageURL,
		IsShared:      request.IsShared,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, mapWishlistResponse(wishlist))
}

func (h handler) getWishlist(w http.ResponseWriter, r *http.Request) {
	wishlist, err := h.service.GetByID(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(wishlist))
}

func (h handler) joinWishlist(w http.ResponseWriter, r *http.Request) {
	wishlist, err := h.service.Join(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(wishlist))
}

func (h handler) patchWishlist(w http.ResponseWriter, r *http.Request) {
	var request patchWishlistRequest
	if err := httpx.DecodeJSON(r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.Patch(r.Context(), r.PathValue("id"), &application.PatchWishlistInput{
		Title:         request.Title,
		Description:   request.Description,
		Year:          request.Year,
		CoverImageURL: request.CoverImageURL,
		IsShared:      request.IsShared,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(wishlist))
}

func (h handler) deleteWishlist(w http.ResponseWriter, r *http.Request) {
	if err := h.service.Delete(r.Context(), r.PathValue("id")); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h handler) archiveWishlist(w http.ResponseWriter, r *http.Request) {
	wishlist, err := h.service.Archive(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(wishlist))
}

func (h handler) restoreWishlist(w http.ResponseWriter, r *http.Request) {
	wishlist, err := h.service.Restore(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(wishlist))
}

func (h handler) addItem(w http.ResponseWriter, r *http.Request) {
	var request createItemRequest
	if err := httpx.DecodeJSON(r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	item, err := h.service.AddItem(r.Context(), r.PathValue("id"), &application.AddItemInput{
		Title:      request.Title,
		Notes:      request.Notes,
		PriceLabel: request.PriceLabel,
		Priority:   request.Priority,
		Status:     request.Status,
		ImageURL:   request.ImageURL,
		ProductURL: request.ProductURL,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, mapItemResponse(item))
}

func (h handler) patchItem(w http.ResponseWriter, r *http.Request) {
	var request patchItemRequest
	if err := httpx.DecodeJSON(r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	item, err := h.service.PatchItem(
		r.Context(),
		r.PathValue("id"),
		r.PathValue("itemId"),
		&application.PatchItemInput{
			Title:      request.Title,
			Notes:      request.Notes,
			PriceLabel: request.PriceLabel,
			Priority:   request.Priority,
			Status:     request.Status,
			ImageURL:   request.ImageURL,
			ProductURL: request.ProductURL,
		},
	)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapItemResponse(item))
}

func (h handler) deleteItem(w http.ResponseWriter, r *http.Request) {
	if err := h.service.DeleteItem(r.Context(), r.PathValue("id"), r.PathValue("itemId")); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h handler) reorderItems(w http.ResponseWriter, r *http.Request) {
	var request reorderItemsRequest
	if err := httpx.DecodeJSON(r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.ReorderItems(r.Context(), r.PathValue("id"), request.OrderedItemIDs)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(wishlist))
}

func (h handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	appErr, ok := application.AsError(err)
	if !ok {
		h.logger.Error("wishlist request failed", "method", r.Method, "path", r.URL.Path, "error", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		return
	}

	switch appErr.Code {
	case application.ErrorCodeValidation:
		httpx.WriteError(w, http.StatusBadRequest, string(appErr.Code), appErr.Message, appErr.Field)
	case application.ErrorCodeWishlistNotFound, application.ErrorCodeItemNotFound:
		httpx.WriteError(w, http.StatusNotFound, string(appErr.Code), appErr.Message, appErr.Field)
	default:
		h.logger.Error("wishlist request failed with unknown application error", "method", r.Method, "path", r.URL.Path, "error", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
	}
}

func mapWishlistResponse(wishlist domain.Wishlist) wishlistResponse {
	sharedUsers := make([]sharedUserResult, 0, len(wishlist.SharedUsers))
	for _, user := range wishlist.SharedUsers {
		sharedUsers = append(sharedUsers, sharedUserResult{
			ID:    user.ID,
			Name:  user.Name,
			Email: user.Email,
			Role:  user.Role,
		})
	}

	items := make([]itemResponse, 0, len(wishlist.Items))
	for _, item := range wishlist.Items {
		items = append(items, mapItemResponse(item))
	}

	return wishlistResponse{
		ID:            wishlist.ID,
		OwnerUserID:   wishlist.OwnerID,
		Title:         wishlist.Title,
		Description:   wishlist.Description,
		Year:          wishlist.Year,
		CoverImageURL: wishlist.CoverImageURL,
		CreatedAt:     wishlist.CreatedAt,
		UpdatedAt:     wishlist.UpdatedAt,
		IsArchived:    wishlist.IsArchived,
		IsShared:      wishlist.IsShared,
		SharedUsers:   sharedUsers,
		Items:         items,
	}
}

func (h handler) addSharedUser(w http.ResponseWriter, r *http.Request) {
	var request addSharedUserRequest
	if err := httpx.DecodeJSON(r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	err := h.service.AddSharedUser(r.Context(), r.PathValue("id"), &application.AddSharedUserInput{
		Name:  request.Name,
		Email: request.Email,
		Role:  request.Role,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h handler) removeSharedUser(w http.ResponseWriter, r *http.Request) {
	if err := h.service.RemoveSharedUser(r.Context(), r.PathValue("id"), r.PathValue("userId")); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func mapItemResponse(item domain.WishlistItem) itemResponse {
	return itemResponse{
		ID:          item.ID,
		Title:       item.Title,
		Rank:        item.Rank,
		Notes:       item.Notes,
		PriceLabel:  item.PriceLabel,
		Priority:    item.Priority,
		Status:      item.Status,
		ImageURL:    item.ImageURL,
		ProductURL:  item.ProductURL,
		PurchasedAt: item.PurchasedAt,
		CreatedAt:   item.CreatedAt,
		UpdatedAt:   item.UpdatedAt,
	}
}
