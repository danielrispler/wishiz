package authhttp

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

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
)

func TestRequireAuthRejectsMissingBearerToken(t *testing.T) {
	t.Parallel()

	mux := http.NewServeMux()
	RegisterRoutes(mux, slog.New(slog.NewTextHandler(io.Discard, nil)), &stubService{})

	request := httptest.NewRequest(http.MethodGet, "/auth/me", http.NoBody)
	recorder := httptest.NewRecorder()

	mux.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", recorder.Code)
	}
}

func TestLogInReturnsTokenAndUser(t *testing.T) {
	t.Parallel()
	service := &stubService{
		logIn: func(_ context.Context, input *application.LogInInput) (domain.User, string, error) {
			if input.Email != "maya@example.com" {
				t.Fatalf("unexpected email %q", input.Email)
			}
			return sampleUser(), "session-token", nil
		},
	}

	response := performRequest(t, service, http.MethodPost, "/auth/login", `{"email":"maya@example.com","password":"secret"}`, "")
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}

	var payload authResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Token != "session-token" {
		t.Fatalf("expected session token, got %q", payload.Token)
	}
	if payload.User.Email != "maya@example.com" {
		t.Fatalf("expected user email, got %q", payload.User.Email)
	}
}

func TestSignUpReturnsTokenAndUser(t *testing.T) {
	t.Parallel()
	service := &stubService{
		signUp: func(_ context.Context, input *application.SignUpInput) (domain.User, string, error) {
			if input.Email != "maya@example.com" {
				t.Fatalf("unexpected email %q", input.Email)
			}
			if input.FullName != "Maya Hope" {
				t.Fatalf("unexpected full name %q", input.FullName)
			}
			return sampleUser(), "signup-token", nil
		},
	}

	response := performRequest(
		t,
		service,
		http.MethodPost,
		"/auth/signup",
		`{"email":"maya@example.com","password":"secret","fullName":"Maya Hope","birthday":"1992-06-15T00:00:00Z","preferredCurrencyCode":"USD","notificationsEnabled":true,"reminderDays":14}`,
		"",
	)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}

	var payload authResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Token != "signup-token" {
		t.Fatalf("expected signup token, got %q", payload.Token)
	}
	if payload.User.Email != "maya@example.com" {
		t.Fatalf("expected user email, got %q", payload.User.Email)
	}
}

func TestGetCurrentUserUsesAuthenticatedContext(t *testing.T) {
	t.Parallel()
	service := &stubService{
		authenticate: func(_ context.Context, token string) (domain.User, error) {
			if token != "session-token" {
				t.Fatalf("unexpected token %q", token)
			}
			return sampleUser(), nil
		},
		getCurrentUser: func(_ context.Context, userID string) (domain.User, error) {
			if userID != sampleUser().ID {
				t.Fatalf("unexpected user id %q", userID)
			}
			return sampleUser(), nil
		},
	}

	response := performRequest(t, service, http.MethodGet, "/auth/me", "", "Bearer session-token")
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d with body %s", response.Code, response.Body.String())
	}
}

type stubService struct {
	signUp            func(context.Context, *application.SignUpInput) (domain.User, string, error)
	logIn             func(context.Context, *application.LogInInput) (domain.User, string, error)
	authenticate      func(context.Context, string) (domain.User, error)
	getCurrentUser    func(context.Context, string) (domain.User, error)
	updateCurrentUser func(context.Context, string, *application.UpdateCurrentUserInput) (domain.User, error)
	savePreferences   func(context.Context, string, []string, []string) (domain.User, error)
	logOut            func(context.Context, string) error
}

func (s *stubService) SignUp(ctx context.Context, input *application.SignUpInput) (domain.User, string, error) {
	if s.signUp == nil {
		return domain.User{}, "", errors.New("unexpected SignUp call")
	}
	return s.signUp(ctx, input)
}

func (s *stubService) LogIn(ctx context.Context, input *application.LogInInput) (domain.User, string, error) {
	if s.logIn == nil {
		return domain.User{}, "", errors.New("unexpected LogIn call")
	}
	return s.logIn(ctx, input)
}

func (s *stubService) Authenticate(ctx context.Context, rawToken string) (domain.User, error) {
	if s.authenticate == nil {
		return domain.User{}, application.Unauthorized("unauthorized")
	}
	return s.authenticate(ctx, rawToken)
}

func (s *stubService) GetCurrentUser(ctx context.Context, userID string) (domain.User, error) {
	if s.getCurrentUser == nil {
		return domain.User{}, errors.New("unexpected GetCurrentUser call")
	}
	return s.getCurrentUser(ctx, userID)
}

func (s *stubService) UpdateCurrentUser(ctx context.Context, userID string, input *application.UpdateCurrentUserInput) (domain.User, error) {
	if s.updateCurrentUser == nil {
		return domain.User{}, errors.New("unexpected UpdateCurrentUser call")
	}
	return s.updateCurrentUser(ctx, userID, input)
}

func (s *stubService) SavePreferences(ctx context.Context, userID string, categories []string, brands []string) (domain.User, error) {
	if s.savePreferences == nil {
		return domain.User{}, errors.New("unexpected SavePreferences call")
	}
	return s.savePreferences(ctx, userID, categories, brands)
}

func (s *stubService) LogOut(ctx context.Context, rawToken string) error {
	if s.logOut == nil {
		return nil
	}
	return s.logOut(ctx, rawToken)
}

func performRequest(t *testing.T, service Service, method string, path string, body string, authorization string) *httptest.ResponseRecorder {
	t.Helper()

	mux := http.NewServeMux()
	RegisterRoutes(mux, slog.New(slog.NewTextHandler(io.Discard, nil)), service)

	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	if authorization != "" {
		request.Header.Set("Authorization", authorization)
	}

	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	return recorder
}

func sampleUser() domain.User {
	return domain.User{
		ID:                    "11111111-1111-1111-1111-111111111111",
		Email:                 "maya@example.com",
		FullName:              "Maya Hope",
		Birthday:              time.Date(1992, 6, 15, 0, 0, 0, 0, time.UTC),
		PreferredCurrencyCode: "USD",
		NotificationsEnabled:  true,
		ReminderDays:          14,
	}
}
