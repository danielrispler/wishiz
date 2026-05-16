package authhttp

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

type Service interface {
	SignUp(ctx context.Context, input *application.SignUpInput) (domain.User, string, error)
	LogIn(ctx context.Context, input *application.LogInInput) (domain.User, string, error)
	Authenticate(ctx context.Context, rawToken string) (domain.User, error)
	GetCurrentUser(ctx context.Context, userID string) (domain.User, error)
	UpdateCurrentUser(ctx context.Context, userID string, input *application.UpdateCurrentUserInput) (domain.User, error)
	SavePreferences(ctx context.Context, userID string, brands []string) (domain.User, error)
	LogOut(ctx context.Context, rawToken string) error
}

type handler struct {
	logger  *slog.Logger
	service Service
}

type signUpRequest struct {
	Email                 string    `json:"email"`
	Password              string    `json:"password"`
	FullName              string    `json:"fullName"`
	Birthday              time.Time `json:"birthday"`
	PreferredCurrencyCode string    `json:"preferredCurrencyCode"`
	NotificationsEnabled  bool      `json:"notificationsEnabled"`
	ReminderDays          int       `json:"reminderDays"`
}

type logInRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type updateCurrentUserRequest struct {
	Email                 string    `json:"email"`
	FullName              string    `json:"fullName"`
	Birthday              time.Time `json:"birthday"`
	PreferredCurrencyCode string    `json:"preferredCurrencyCode"`
	NotificationsEnabled  bool      `json:"notificationsEnabled"`
	ReminderDays          int       `json:"reminderDays"`
	CurrentPassword       string    `json:"currentPassword"`
	NewPassword           string    `json:"newPassword"`
}

type savePreferencesRequest struct {
	Brands []string `json:"brands"`
}

type authResponse struct {
	Token string       `json:"token"`
	User  userResponse `json:"user"`
}

type userResponse struct {
	ID                    string    `json:"id"`
	Email                 string    `json:"email"`
	FullName              string    `json:"fullName"`
	Birthday              time.Time `json:"birthday"`
	PreferredCurrencyCode string    `json:"preferredCurrencyCode"`
	NotificationsEnabled  bool      `json:"notificationsEnabled"`
	ReminderDays          int       `json:"reminderDays"`
	PreferredBrands       []string  `json:"preferredBrands"`
}

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, service Service) {
	h := handler{logger: logger, service: service}

	mux.HandleFunc("POST /auth/signup", h.signUp)
	mux.HandleFunc("POST /auth/login", h.logIn)
	mux.HandleFunc("GET /auth/me", RequireAuth(service, h.getCurrentUser))
	mux.HandleFunc("PATCH /auth/me", RequireAuth(service, h.updateCurrentUser))
	mux.HandleFunc("PATCH /auth/me/onboarding", RequireAuth(service, h.savePreferences))
	mux.HandleFunc("POST /auth/logout", RequireAuth(service, h.logOut))
}

func RequireAuth(service Service, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rawToken := bearerToken(r.Header.Get("Authorization"))
		if rawToken == "" {
			httpx.WriteError(w, http.StatusUnauthorized, string(application.ErrorCodeUnauthorized), "authorization is required", "")
			return
		}

		user, err := service.Authenticate(r.Context(), rawToken)
		if err != nil {
			if appErr, ok := application.AsError(err); ok {
				httpx.WriteError(w, http.StatusUnauthorized, string(appErr.Code), appErr.Message, appErr.Field)
				return
			}
			httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
			return
		}

		ctx := authctx.WithUser(r.Context(), authctx.User{
			ID:    user.ID,
			Email: user.Email,
		})
		next(w, r.WithContext(ctx))
	}
}

func (h handler) signUp(w http.ResponseWriter, r *http.Request) {
	var request signUpRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	user, token, err := h.service.SignUp(r.Context(), &application.SignUpInput{
		Email:                 request.Email,
		Password:              request.Password,
		FullName:              request.FullName,
		Birthday:              request.Birthday,
		PreferredCurrencyCode: request.PreferredCurrencyCode,
		NotificationsEnabled:  request.NotificationsEnabled,
		ReminderDays:          request.ReminderDays,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, authResponse{Token: token, User: mapUser(user)})
}

func (h handler) logIn(w http.ResponseWriter, r *http.Request) {
	var request logInRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	user, token, err := h.service.LogIn(r.Context(), &application.LogInInput{
		Email:    request.Email,
		Password: request.Password,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, authResponse{Token: token, User: mapUser(user)})
}

func (h handler) getCurrentUser(w http.ResponseWriter, r *http.Request) {
	user, ok := authctx.UserFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, string(application.ErrorCodeUnauthorized), "authorization is required", "")
		return
	}

	currentUser, err := h.service.GetCurrentUser(r.Context(), user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapUser(currentUser))
}

func (h handler) updateCurrentUser(w http.ResponseWriter, r *http.Request) {
	user, ok := authctx.UserFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, string(application.ErrorCodeUnauthorized), "authorization is required", "")
		return
	}

	var request updateCurrentUserRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	updatedUser, err := h.service.UpdateCurrentUser(r.Context(), user.ID, &application.UpdateCurrentUserInput{
		Email:                 request.Email,
		FullName:              request.FullName,
		Birthday:              request.Birthday,
		PreferredCurrencyCode: request.PreferredCurrencyCode,
		NotificationsEnabled:  request.NotificationsEnabled,
		ReminderDays:          request.ReminderDays,
		CurrentPassword:       request.CurrentPassword,
		NewPassword:           request.NewPassword,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapUser(updatedUser))
}

func (h handler) savePreferences(w http.ResponseWriter, r *http.Request) {
	user, ok := authctx.UserFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, string(application.ErrorCodeUnauthorized), "authorization is required", "")
		return
	}

	var request savePreferencesRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}
	if request.Brands == nil {
		request.Brands = []string{}
	}

	updatedUser, err := h.service.SavePreferences(r.Context(), user.ID, request.Brands)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, mapUser(updatedUser))
}

func (h handler) logOut(w http.ResponseWriter, r *http.Request) {
	if err := h.service.LogOut(r.Context(), bearerToken(r.Header.Get("Authorization"))); err != nil {
		h.writeError(w, r, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	appErr, ok := application.AsError(err)
	if !ok {
		h.logger.Error("auth request failed", "method", r.Method, "path", r.URL.Path, "error", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		return
	}

	switch appErr.Code {
	case application.ErrorCodeValidation:
		httpx.WriteError(w, http.StatusBadRequest, string(appErr.Code), appErr.Message, appErr.Field)
	case application.ErrorCodeUnauthorized:
		httpx.WriteError(w, http.StatusUnauthorized, string(appErr.Code), appErr.Message, appErr.Field)
	case application.ErrorCodeConflict:
		httpx.WriteError(w, http.StatusConflict, string(appErr.Code), appErr.Message, appErr.Field)
	case application.ErrorCodeNotFound:
		httpx.WriteError(w, http.StatusNotFound, string(appErr.Code), appErr.Message, appErr.Field)
	default:
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
	}
}

func mapUser(user domain.User) userResponse {
	brands := user.PreferredBrands
	if brands == nil {
		brands = []string{}
	}
	return userResponse{
		ID:                    user.ID,
		Email:                 user.Email,
		FullName:              user.FullName,
		Birthday:              user.Birthday,
		PreferredCurrencyCode: user.PreferredCurrencyCode,
		NotificationsEnabled:  user.NotificationsEnabled,
		ReminderDays:          user.ReminderDays,
		PreferredBrands:       brands,
	}
}

func bearerToken(header string) string {
	header = strings.TrimSpace(header)
	if !strings.HasPrefix(strings.ToLower(header), "bearer ") {
		return ""
	}
	return strings.TrimSpace(header[len("Bearer "):])
}
