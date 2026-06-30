package http

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

// Service is the inbox application surface the handlers depend on.
type Service interface {
	List(ctx context.Context, userID string, limit, offset int) ([]domain.Notification, error)
	UnreadCount(ctx context.Context, userID string) (int, error)
	MarkRead(ctx context.Context, userID, notificationID string) error
	MarkAllRead(ctx context.Context, userID string) (int, error)
	RegisterDevice(ctx context.Context, userID, token, platform string) error
	DeregisterDevice(ctx context.Context, userID, token string) error
	ListMutes(ctx context.Context, userID string) ([]string, error)
	Mute(ctx context.Context, userID, wishlistID string) error
	Unmute(ctx context.Context, userID, wishlistID string) error
}

type AuthMiddleware func(http.HandlerFunc) http.HandlerFunc

type handler struct {
	logger  *slog.Logger
	service Service
}

type notificationResponse struct {
	ID          string     `json:"id"`
	Type        string     `json:"type"`
	Title       string     `json:"title"`
	Body        string     `json:"body"`
	WishlistID  *string    `json:"wishlistId"`
	ItemID      *string    `json:"itemId"`
	ImportJobID *string    `json:"importJobId"`
	ReadAt      *time.Time `json:"readAt"`
	CreatedAt   time.Time  `json:"createdAt"`
}

type registerDeviceRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"`
}

type deregisterDeviceRequest struct {
	Token string `json:"token"`
}

type muteRequest struct {
	WishlistID string `json:"wishlistId"`
}

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, service Service, authMiddleware AuthMiddleware) {
	if authMiddleware == nil {
		authMiddleware = func(next http.HandlerFunc) http.HandlerFunc { return next }
	}
	h := handler{logger: logger, service: service}

	mux.HandleFunc("GET /notifications", authMiddleware(withAuthenticatedUser(h.list)))
	mux.HandleFunc("GET /notifications/unread-count", authMiddleware(withAuthenticatedUser(h.unreadCount)))
	mux.HandleFunc("POST /notifications/{id}/read", authMiddleware(withAuthenticatedUser(h.markRead)))
	mux.HandleFunc("POST /notifications/read-all", authMiddleware(withAuthenticatedUser(h.markAllRead)))
	mux.HandleFunc("POST /notifications/devices", authMiddleware(withAuthenticatedUser(h.registerDevice)))
	mux.HandleFunc("DELETE /notifications/devices", authMiddleware(withAuthenticatedUser(h.deregisterDevice)))
	mux.HandleFunc("GET /notifications/mutes", authMiddleware(withAuthenticatedUser(h.listMutes)))
	mux.HandleFunc("POST /notifications/mutes", authMiddleware(withAuthenticatedUser(h.mute)))
	mux.HandleFunc("DELETE /notifications/mutes/{wishlistId}", authMiddleware(withAuthenticatedUser(h.unmute)))
}

func withAuthenticatedUser(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authctx.UserFromContext(r.Context()); !ok {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
			return
		}
		next(w, r)
	}
}

func (h handler) list(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	notifications, err := h.service.List(r.Context(), user.ID, limit, offset)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	response := make([]notificationResponse, 0, len(notifications))
	for _, n := range notifications {
		response = append(response, mapNotification(n))
	}
	httpx.WriteJSON(w, http.StatusOK, response)
}

func (h handler) unreadCount(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	count, err := h.service.UnreadCount(r.Context(), user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]int{"count": count})
}

func (h handler) markRead(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	if err := h.service.MarkRead(r.Context(), user.ID, r.PathValue("id")); err != nil {
		h.writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h handler) markAllRead(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	count, err := h.service.MarkAllRead(r.Context(), user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]int{"markedRead": count})
}

func (h handler) registerDevice(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	var request registerDeviceRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}
	if err := h.service.RegisterDevice(r.Context(), user.ID, request.Token, request.Platform); err != nil {
		h.writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h handler) deregisterDevice(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	var request deregisterDeviceRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}
	if err := h.service.DeregisterDevice(r.Context(), user.ID, request.Token); err != nil {
		h.writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h handler) listMutes(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	wishlistIDs, err := h.service.ListMutes(r.Context(), user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	if wishlistIDs == nil {
		wishlistIDs = []string{}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string][]string{"wishlistIds": wishlistIDs})
}

func (h handler) mute(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	var request muteRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}
	if err := h.service.Mute(r.Context(), user.ID, request.WishlistID); err != nil {
		h.writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h handler) unmute(w http.ResponseWriter, r *http.Request) {
	user, _ := authctx.UserFromContext(r.Context())
	if err := h.service.Unmute(r.Context(), user.ID, r.PathValue("wishlistId")); err != nil {
		h.writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	if appErr, ok := application.AsError(err); ok {
		switch appErr.Code {
		case application.ErrorCodeValidation:
			httpx.WriteError(w, http.StatusBadRequest, string(appErr.Code), appErr.Message, appErr.Field)
		case application.ErrorCodeNotFound:
			httpx.WriteError(w, http.StatusNotFound, string(appErr.Code), appErr.Message, appErr.Field)
		default:
			httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		}
		return
	}
	h.logger.Error("notification request failed", "method", r.Method, "path", r.URL.Path, "error", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
}

func mapNotification(n domain.Notification) notificationResponse {
	return notificationResponse{
		ID:          n.ID,
		Type:        n.Type,
		Title:       n.Title,
		Body:        n.Body,
		WishlistID:  n.WishlistID,
		ItemID:      n.ItemID,
		ImportJobID: n.ImportJobID,
		ReadAt:      n.ReadAt,
		CreatedAt:   n.CreatedAt,
	}
}
