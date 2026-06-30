package http

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

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
)

const testUserID = "11111111-1111-1111-1111-111111111111"

func TestListRequiresAuth(t *testing.T) {
	t.Parallel()
	// nil authMiddleware -> identity -> withAuthenticatedUser sees no user -> 401.
	response := performRequest(t, &stubService{}, http.MethodGet, "/notifications", "", false)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
}

func TestListReturnsNotifications(t *testing.T) {
	t.Parallel()
	service := &stubService{
		list: func(_ context.Context, userID string, _, _ int) ([]domain.Notification, error) {
			if userID != testUserID {
				t.Fatalf("unexpected user id %q", userID)
			}
			return []domain.Notification{{ID: "n1", Type: domain.TypeItemAdded, Title: "Maya added an item"}}, nil
		},
	}
	response := performRequest(t, service, http.MethodGet, "/notifications", "", true)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body %s", response.Code, response.Body.String())
	}
	var payload []notificationResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(payload) != 1 || payload[0].ID != "n1" {
		t.Fatalf("unexpected payload %+v", payload)
	}
}

func TestUnreadCountReturnsCount(t *testing.T) {
	t.Parallel()
	service := &stubService{
		unreadCount: func(_ context.Context, _ string) (int, error) { return 3, nil },
	}
	response := performRequest(t, service, http.MethodGet, "/notifications/unread-count", "", true)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", response.Code)
	}
	var payload map[string]int
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload["count"] != 3 {
		t.Fatalf("expected count 3, got %d", payload["count"])
	}
}

func TestMarkReadNoContent(t *testing.T) {
	t.Parallel()
	service := &stubService{
		markRead: func(_ context.Context, _, id string) error {
			if id != "n1" {
				t.Fatalf("unexpected id %q", id)
			}
			return nil
		},
	}
	response := performRequest(t, service, http.MethodPost, "/notifications/n1/read", "", true)
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", response.Code)
	}
}

func TestMarkReadNotFound(t *testing.T) {
	t.Parallel()
	service := &stubService{
		markRead: func(_ context.Context, _, _ string) error { return application.NotFound() },
	}
	response := performRequest(t, service, http.MethodPost, "/notifications/n1/read", "", true)
	if response.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", response.Code)
	}
}

func TestRegisterDeviceValidationError(t *testing.T) {
	t.Parallel()
	service := &stubService{
		registerDevice: func(_ context.Context, _, _, _ string) error {
			return application.ValidationError("platform", "platform must be ios or android")
		},
	}
	response := performRequest(
		t, service, http.MethodPost, "/notifications/devices", `{"token":"abc","platform":"windows"}`, true,
	)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", response.Code)
	}
}

func TestDeregisterDeviceForwardsAuthenticatedUser(t *testing.T) {
	t.Parallel()
	var gotUserID, gotToken string
	service := &stubService{
		deregisterDevice: func(_ context.Context, userID, token string) error {
			gotUserID, gotToken = userID, token
			return nil
		},
	}
	response := performRequest(
		t, service, http.MethodDelete, "/notifications/devices", `{"token":"tok-a"}`, true,
	)
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body %s", response.Code, response.Body.String())
	}
	if gotUserID != testUserID {
		t.Fatalf("deregister must be scoped to the caller; got userID %q want %q", gotUserID, testUserID)
	}
	if gotToken != "tok-a" {
		t.Fatalf("unexpected token %q", gotToken)
	}
}

func TestMuteNoContent(t *testing.T) {
	t.Parallel()
	service := &stubService{
		mute: func(_ context.Context, _, wishlistID string) error {
			if wishlistID != "w1" {
				t.Fatalf("unexpected wishlist id %q", wishlistID)
			}
			return nil
		},
	}
	response := performRequest(t, service, http.MethodPost, "/notifications/mutes", `{"wishlistId":"w1"}`, true)
	if response.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d body %s", response.Code, response.Body.String())
	}
}

// --- harness ---

type stubService struct {
	list             func(context.Context, string, int, int) ([]domain.Notification, error)
	unreadCount      func(context.Context, string) (int, error)
	markRead         func(context.Context, string, string) error
	markAllRead      func(context.Context, string) (int, error)
	registerDevice   func(context.Context, string, string, string) error
	deregisterDevice func(context.Context, string, string) error
	listMutes        func(context.Context, string) ([]string, error)
	mute             func(context.Context, string, string) error
	unmute           func(context.Context, string, string) error
}

func (s *stubService) List(ctx context.Context, userID string, limit, offset int) ([]domain.Notification, error) {
	if s.list == nil {
		return nil, errors.New("unexpected List call")
	}
	return s.list(ctx, userID, limit, offset)
}

func (s *stubService) UnreadCount(ctx context.Context, userID string) (int, error) {
	if s.unreadCount == nil {
		return 0, errors.New("unexpected UnreadCount call")
	}
	return s.unreadCount(ctx, userID)
}

func (s *stubService) MarkRead(ctx context.Context, userID, id string) error {
	if s.markRead == nil {
		return errors.New("unexpected MarkRead call")
	}
	return s.markRead(ctx, userID, id)
}

func (s *stubService) MarkAllRead(ctx context.Context, userID string) (int, error) {
	if s.markAllRead == nil {
		return 0, errors.New("unexpected MarkAllRead call")
	}
	return s.markAllRead(ctx, userID)
}

func (s *stubService) RegisterDevice(ctx context.Context, userID, token, platform string) error {
	if s.registerDevice == nil {
		return errors.New("unexpected RegisterDevice call")
	}
	return s.registerDevice(ctx, userID, token, platform)
}

func (s *stubService) DeregisterDevice(ctx context.Context, userID, token string) error {
	if s.deregisterDevice == nil {
		return errors.New("unexpected DeregisterDevice call")
	}
	return s.deregisterDevice(ctx, userID, token)
}

func (s *stubService) ListMutes(ctx context.Context, userID string) ([]string, error) {
	if s.listMutes == nil {
		return nil, errors.New("unexpected ListMutes call")
	}
	return s.listMutes(ctx, userID)
}

func (s *stubService) Mute(ctx context.Context, userID, wishlistID string) error {
	if s.mute == nil {
		return errors.New("unexpected Mute call")
	}
	return s.mute(ctx, userID, wishlistID)
}

func (s *stubService) Unmute(ctx context.Context, userID, wishlistID string) error {
	if s.unmute == nil {
		return errors.New("unexpected Unmute call")
	}
	return s.unmute(ctx, userID, wishlistID)
}

func performRequest(
	t *testing.T, service Service, method, path, body string, withUser bool,
) *httptest.ResponseRecorder {
	t.Helper()

	mux := http.NewServeMux()
	var authMiddleware AuthMiddleware
	if withUser {
		authMiddleware = func(next http.HandlerFunc) http.HandlerFunc {
			return func(w http.ResponseWriter, r *http.Request) {
				ctx := authctx.WithUser(r.Context(), authctx.User{ID: testUserID, Email: "u@example.com"})
				next(w, r.WithContext(ctx))
			}
		}
	}
	RegisterRoutes(mux, slog.New(slog.NewTextHandler(io.Discard, nil)), service, authMiddleware)

	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	return recorder
}
