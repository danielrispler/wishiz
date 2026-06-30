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
	CreateInvite(ctx context.Context, wishlistID string, input *application.CreateInviteInput) (domain.WishlistInvite, error)
	DeleteInvite(ctx context.Context, wishlistID string, inviteID string) error
	RemoveMember(ctx context.Context, wishlistID string, userID string) error
	UpdateMemberRole(ctx context.Context, wishlistID string, userID string, input *application.PatchWishlistMemberInput) error
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
	Join(ctx context.Context, id string, input *application.JoinWishlistInput) (domain.Wishlist, error)
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
}

type patchWishlistRequest struct {
	Title         application.PatchField[string]  `json:"title"`
	Description   application.PatchField[string]  `json:"description"`
	Year          application.PatchField[int]     `json:"year"`
	CoverImageURL application.PatchField[*string] `json:"coverImageUrl"`
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

type createInviteRequest struct {
	Email     *string    `json:"email"`
	Role      string     `json:"role"`
	ExpiresAt *time.Time `json:"expiresAt"`
}

type joinWishlistRequest struct {
	Token string `json:"token"`
}

type patchMemberRequest struct {
	Role string `json:"role"`
}

type wishlistResponse struct {
	ID            string            `json:"id"`
	OwnerUserID   string            `json:"ownerUserId"`
	OwnerFullName string            `json:"ownerFullName"`
	Title         string            `json:"title"`
	Description   string            `json:"description"`
	Year          int               `json:"year"`
	CoverImageURL *string           `json:"coverImageUrl"`
	CreatedAt     time.Time         `json:"createdAt"`
	UpdatedAt     time.Time         `json:"updatedAt"`
	IsArchived    bool              `json:"isArchived"`
	Members       []memberResponse  `json:"members"`
	Invites       *[]inviteResponse `json:"invites,omitempty"`
	Items         []itemResponse    `json:"items"`
}

type memberResponse struct {
	UserID    string    `json:"userId"`
	Email     string    `json:"email"`
	FullName  string    `json:"fullName"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type inviteResponse struct {
	ID              string     `json:"id"`
	Email           *string    `json:"email"`
	Role            string     `json:"role"`
	InvitedByUserID *string    `json:"invitedByUserId"`
	AcceptedAt      *time.Time `json:"acceptedAt"`
	ExpiresAt       time.Time  `json:"expiresAt"`
	CreatedAt       time.Time  `json:"createdAt"`
	UpdatedAt       time.Time  `json:"updatedAt"`
	Token           string     `json:"token,omitempty"`
}

type itemResponse struct {
	ID                string     `json:"id"`
	Title             string     `json:"title"`
	Rank              int        `json:"rank"`
	Notes             *string    `json:"notes"`
	PriceLabel        *string    `json:"priceLabel"`
	PriceAmount       *string    `json:"priceAmount"`
	PriceAmountMax    *string    `json:"priceAmountMax"`
	PriceCurrencyCode *string    `json:"priceCurrencyCode"`
	Priority          string     `json:"priority"`
	Status            string     `json:"status"`
	ImageURL          *string    `json:"imageUrl"`
	ProductURL        *string    `json:"productUrl"`
	PurchasedAt       *time.Time `json:"purchasedAt"`
	CreatedAt         time.Time  `json:"createdAt"`
	UpdatedAt         time.Time  `json:"updatedAt"`
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
	mux.HandleFunc("POST /wishlists/{id}/invites", authMiddleware(withAuthenticatedUser(h.createInvite)))
	mux.HandleFunc("DELETE /wishlists/{id}/invites/{inviteId}", authMiddleware(withAuthenticatedUser(h.deleteInvite)))
	mux.HandleFunc("DELETE /wishlists/{id}/members/{userId}", authMiddleware(withAuthenticatedUser(h.removeMember)))
	mux.HandleFunc("PATCH /wishlists/{id}/members/{userId}", authMiddleware(withAuthenticatedUser(h.patchMember)))
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
		response = append(response, mapWishlistResponse(r.Context(), wishlist))
	}

	httpx.WriteJSON(w, http.StatusOK, response)
}

func (h handler) createWishlist(w http.ResponseWriter, r *http.Request) {
	var request createWishlistRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.Create(r.Context(), &application.CreateWishlistInput{
		Title:         request.Title,
		Description:   request.Description,
		Year:          request.Year,
		CoverImageURL: request.CoverImageURL,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, mapWishlistResponse(r.Context(), wishlist))
}

func (h handler) getWishlist(w http.ResponseWriter, r *http.Request) {
	wishlist, err := h.service.GetByID(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(r.Context(), wishlist))
}

func (h handler) joinWishlist(w http.ResponseWriter, r *http.Request) {
	var request joinWishlistRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.Join(r.Context(), r.PathValue("id"), &application.JoinWishlistInput{
		Token: request.Token,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(r.Context(), wishlist))
}

func (h handler) patchWishlist(w http.ResponseWriter, r *http.Request) {
	var request patchWishlistRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.Patch(r.Context(), r.PathValue("id"), &application.PatchWishlistInput{
		Title:         request.Title,
		Description:   request.Description,
		Year:          request.Year,
		CoverImageURL: request.CoverImageURL,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(r.Context(), wishlist))
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

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(r.Context(), wishlist))
}

func (h handler) restoreWishlist(w http.ResponseWriter, r *http.Request) {
	wishlist, err := h.service.Restore(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(r.Context(), wishlist))
}

func (h handler) addItem(w http.ResponseWriter, r *http.Request) {
	var request createItemRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
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
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
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
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	wishlist, err := h.service.ReorderItems(r.Context(), r.PathValue("id"), request.OrderedItemIDs)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapWishlistResponse(r.Context(), wishlist))
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

func mapWishlistResponse(ctx context.Context, wishlist domain.Wishlist) wishlistResponse {
	user, _ := authctx.UserFromContext(ctx)
	isOwner := user.ID != "" && wishlist.OwnerID == user.ID

	members := make([]memberResponse, 0, len(wishlist.Members))
	for _, member := range wishlist.Members {
		members = append(members, memberResponse{
			UserID:    member.UserID,
			Email:     member.Email,
			FullName:  member.FullName,
			Role:      member.Role,
			CreatedAt: member.CreatedAt,
			UpdatedAt: member.UpdatedAt,
		})
	}

	var invites *[]inviteResponse
	if isOwner {
		ownerInvites := make([]inviteResponse, 0, len(wishlist.Invites))
		for _, invite := range wishlist.Invites {
			ownerInvites = append(ownerInvites, mapInviteResponse(invite))
		}
		invites = &ownerInvites
	}

	items := make([]itemResponse, 0, len(wishlist.Items))
	for _, item := range wishlist.Items {
		items = append(items, mapItemResponse(item))
	}

	return wishlistResponse{
		ID:            wishlist.ID,
		OwnerUserID:   wishlist.OwnerID,
		OwnerFullName: wishlist.OwnerFullName,
		Title:         wishlist.Title,
		Description:   wishlist.Description,
		Year:          wishlist.Year,
		CoverImageURL: wishlist.CoverImageURL,
		CreatedAt:     wishlist.CreatedAt,
		UpdatedAt:     wishlist.UpdatedAt,
		IsArchived:    wishlist.IsArchived,
		Members:       members,
		Invites:       invites,
		Items:         items,
	}
}

func mapInviteResponse(invite domain.WishlistInvite) inviteResponse {
	return inviteResponse{
		ID:              invite.ID,
		Email:           invite.Email,
		Role:            invite.Role,
		InvitedByUserID: invite.InvitedByUserID,
		AcceptedAt:      invite.AcceptedAt,
		ExpiresAt:       invite.ExpiresAt,
		CreatedAt:       invite.CreatedAt,
		UpdatedAt:       invite.UpdatedAt,
		Token:           invite.Token,
	}
}

func (h handler) createInvite(w http.ResponseWriter, r *http.Request) {
	var request createInviteRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	invite, err := h.service.CreateInvite(r.Context(), r.PathValue("id"), &application.CreateInviteInput{
		Email:     request.Email,
		Role:      request.Role,
		ExpiresAt: request.ExpiresAt,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, mapInviteResponse(invite))
}

func (h handler) deleteInvite(w http.ResponseWriter, r *http.Request) {
	if err := h.service.DeleteInvite(r.Context(), r.PathValue("id"), r.PathValue("inviteId")); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h handler) removeMember(w http.ResponseWriter, r *http.Request) {
	if err := h.service.RemoveMember(r.Context(), r.PathValue("id"), r.PathValue("userId")); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h handler) patchMember(w http.ResponseWriter, r *http.Request) {
	var request patchMemberRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	if err := h.service.UpdateMemberRole(r.Context(), r.PathValue("id"), r.PathValue("userId"), &application.PatchWishlistMemberInput{
		Role: request.Role,
	}); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func mapItemResponse(item domain.WishlistItem) itemResponse {
	return itemResponse{
		ID:                item.ID,
		Title:             item.Title,
		Rank:              item.Rank,
		Notes:             item.Notes,
		PriceLabel:        item.PriceLabel,
		PriceAmount:       item.PriceAmount,
		PriceAmountMax:    item.PriceAmountMax,
		PriceCurrencyCode: item.PriceCurrencyCode,
		Priority:          item.Priority,
		Status:            item.Status,
		ImageURL:          item.ImageURL,
		ProductURL:        item.ProductURL,
		PurchasedAt:       item.PurchasedAt,
		CreatedAt:         item.CreatedAt,
		UpdatedAt:         item.UpdatedAt,
	}
}
