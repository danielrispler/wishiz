package application

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/ports"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/randhex"
)

const sessionDuration = 30 * 24 * time.Hour

// ImageGarbageCollector removes the user's uploaded storage objects on account
// deletion. It is a structural local interface (no storage/uploads import) so the
// auth package stays decoupled, mirroring the Notifier pattern. Both methods are
// best-effort: an account deletion must never fail because image cleanup failed.
type ImageGarbageCollector interface {
	// CollectOwnedImageKeys reads the user's owned image object keys. Called
	// BEFORE the cascade delete (while the rows still exist); returns nil on error.
	CollectOwnedImageKeys(ctx context.Context, userID string) []string
	// DeleteObjects removes the given keys. Called AFTER the user row is gone so a
	// failed delete never orphans live data; logs and swallows per-object errors.
	DeleteObjects(ctx context.Context, keys []string)
}

type Service struct {
	repo         ports.Repository
	nowFn        func() time.Time
	imageGC      ImageGarbageCollector
	imageGCAsync bool
}

func NewService(repo ports.Repository) *Service {
	return &Service{
		repo:  repo,
		nowFn: time.Now,
	}
}

// WithImageGC attaches a best-effort uploaded-image collector used during account
// deletion. nil-safe: when unset (uploads disabled), deletion skips image cleanup.
func (s *Service) WithImageGC(gc ImageGarbageCollector) *Service {
	s.imageGC = gc
	return s
}

// WithImageGCAsync runs the post-delete object removal on a detached goroutine so
// it never blocks the DELETE /auth/me response (one GCS RPC per object, serial).
// Enabled in the api/all role where a human waits on the request; left off in
// tests so the collect→delete→delete-objects ordering stays deterministic. Object
// cleanup is best-effort either way, so losing it to scale-to-zero CPU throttling
// after the response is the same accepted tradeoff as the detached notification
// push.
func (s *Service) WithImageGCAsync() *Service {
	s.imageGCAsync = true
	return s
}

type SignUpInput struct {
	Email                 string
	Password              string
	FullName              string
	Birthday              *time.Time
	Gender                *string
	PreferredCurrencyCode string
	NotificationsEnabled  bool
	ReminderDays          int
}

type LogInInput struct {
	Email    string
	Password string
}

type UpdateCurrentUserInput struct {
	Email                 string
	FullName              string
	Birthday              *time.Time
	Gender                *string
	PreferredCurrencyCode string
	NotificationsEnabled  bool
	ReminderDays          int
	CurrentPassword       string
	NewPassword           string
}

func (s *Service) SignUp(ctx context.Context, input *SignUpInput) (domain.User, string, error) {
	if input == nil {
		return domain.User{}, "", ValidationError("input", "input is required")
	}

	params, err := s.normalizeCreateInput(input)
	if err != nil {
		return domain.User{}, "", err
	}

	user, err := s.repo.CreateUser(ctx, params)
	if errors.Is(err, ports.ErrEmailConflict) {
		return domain.User{}, "", Conflict("email", "an account with that email already exists")
	}
	if err != nil {
		return domain.User{}, "", err
	}

	token, err := s.createSession(ctx, user.ID)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

func (s *Service) LogIn(ctx context.Context, input *LogInInput) (domain.User, string, error) {
	if input == nil {
		return domain.User{}, "", ValidationError("input", "input is required")
	}

	email := normalizeEmail(input.Email)
	if email == "" {
		return domain.User{}, "", ValidationError("email", "email is required")
	}
	if strings.TrimSpace(input.Password) == "" {
		return domain.User{}, "", ValidationError("password", "password is required")
	}

	user, passwordHash, err := s.repo.GetUserByEmail(ctx, email)
	if errors.Is(err, ports.ErrNotFound) {
		return domain.User{}, "", Unauthorized("email or password is incorrect")
	}
	if err != nil {
		return domain.User{}, "", err
	}
	if bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(input.Password)) != nil {
		return domain.User{}, "", Unauthorized("email or password is incorrect")
	}

	token, err := s.createSession(ctx, user.ID)
	if err != nil {
		return domain.User{}, "", err
	}

	return user, token, nil
}

func (s *Service) Authenticate(ctx context.Context, rawToken string) (domain.User, error) {
	token := strings.TrimSpace(rawToken)
	if token == "" {
		return domain.User{}, Unauthorized("authorization is required")
	}

	user, err := s.repo.GetUserBySessionTokenHash(ctx, tokenHash(token))
	if errors.Is(err, ports.ErrNotFound) {
		return domain.User{}, Unauthorized("session is invalid or expired")
	}
	if err != nil {
		return domain.User{}, err
	}

	return user, nil
}

func (s *Service) GetCurrentUser(ctx context.Context, userID string) (domain.User, error) {
	user, _, err := s.repo.GetUserByID(ctx, userID)
	if errors.Is(err, ports.ErrNotFound) {
		return domain.User{}, NotFound("user not found")
	}
	return user, err
}

func (s *Service) UpdateCurrentUser(ctx context.Context, userID string, input *UpdateCurrentUserInput) (domain.User, error) {
	if input == nil {
		return domain.User{}, ValidationError("input", "input is required")
	}

	currentUser, existingPasswordHash, err := s.repo.GetUserByID(ctx, userID)
	if errors.Is(err, ports.ErrNotFound) {
		return domain.User{}, NotFound("user not found")
	}
	if err != nil {
		return domain.User{}, err
	}

	email := normalizeEmail(input.Email)
	if email == "" {
		return domain.User{}, ValidationError("email", "email is required")
	}
	fullName := strings.TrimSpace(input.FullName)
	if fullName == "" {
		return domain.User{}, ValidationError("fullName", "full name is required")
	}

	passwordHash := existingPasswordHash
	if strings.TrimSpace(input.NewPassword) != "" {
		if strings.TrimSpace(input.CurrentPassword) == "" {
			return domain.User{}, ValidationError("currentPassword", "current password is required")
		}
		if bcrypt.CompareHashAndPassword([]byte(existingPasswordHash), []byte(input.CurrentPassword)) != nil {
			return domain.User{}, Unauthorized("current password is incorrect")
		}
		passwordHash, err = hashPassword(input.NewPassword)
		if err != nil {
			return domain.User{}, err
		}
	}

	updated, err := s.repo.UpdateUser(ctx, ports.UpdateUserParams{
		ID:                    currentUser.ID,
		Email:                 email,
		FullName:              fullName,
		Birthday:              utcOrNil(input.Birthday),
		Gender:                normalizeGender(input.Gender),
		PasswordHash:          passwordHash,
		PreferredCurrencyCode: normalizeCurrencyCode(input.PreferredCurrencyCode),
		NotificationsEnabled:  input.NotificationsEnabled,
		ReminderDays:          normalizeReminderDays(input.ReminderDays),
		PreferredBrands:       currentUser.PreferredBrands,
	})
	if errors.Is(err, ports.ErrEmailConflict) {
		return domain.User{}, Conflict("email", "an account with that email already exists")
	}
	if err != nil {
		return domain.User{}, err
	}

	return updated, nil
}

func (s *Service) SavePreferences(ctx context.Context, userID string, rawBrands []string, gender *string) (domain.User, error) {
	if strings.TrimSpace(userID) == "" {
		return domain.User{}, ValidationError("userID", "userID is required")
	}
	brands, err := parseBrands(rawBrands)
	if err != nil {
		return domain.User{}, err
	}
	user, passwordHash, err := s.repo.GetUserByID(ctx, userID)
	if errors.Is(err, ports.ErrNotFound) {
		return domain.User{}, NotFound("user not found")
	}
	if err != nil {
		return domain.User{}, err
	}
	user, err = s.repo.UpdateUser(ctx, ports.UpdateUserParams{
		ID:                    user.ID,
		Email:                 user.Email,
		FullName:              user.FullName,
		Birthday:              utcOrNil(user.Birthday),
		Gender:                normalizeGender(gender),
		PasswordHash:          passwordHash,
		PreferredCurrencyCode: user.PreferredCurrencyCode,
		NotificationsEnabled:  user.NotificationsEnabled,
		ReminderDays:          user.ReminderDays,
		PreferredBrands:       brands,
	})
	if errors.Is(err, ports.ErrNotFound) {
		return domain.User{}, NotFound("user not found")
	}
	return user, err
}

func parseBrands(raw []string) ([]string, error) {
	if len(raw) > 50 {
		return nil, ValidationError("brands", "too many brands selected (max 50)")
	}
	brands := make([]string, 0, len(raw))
	for _, s := range raw {
		b := strings.TrimSpace(s)
		if b == "" {
			continue
		}
		if len(b) > 100 {
			return nil, ValidationError("brands", fmt.Sprintf("brand name too long: %q", b))
		}
		brands = append(brands, b)
	}
	return brands, nil
}

func (s *Service) GetPreferences(ctx context.Context, userID string) ([]string, error) {
	user, _, err := s.repo.GetUserByID(ctx, userID)
	if errors.Is(err, ports.ErrNotFound) {
		return nil, NotFound("user not found")
	}
	if err != nil {
		return nil, err
	}
	return user.PreferredBrands, nil
}

func (s *Service) LogOut(ctx context.Context, rawToken string) error {
	token := strings.TrimSpace(rawToken)
	if token == "" {
		return nil
	}
	err := s.repo.DeleteSessionByTokenHash(ctx, tokenHash(token))
	if errors.Is(err, ports.ErrNotFound) {
		return nil
	}
	return err
}

// DeleteAccount hard-deletes the user after verifying their password. The DB
// cascade removes sessions, owned wishlists (and their items/members/invites),
// imports, notifications, device tokens and saves. Uploaded image objects are
// collected before the delete (rows still exist) and removed after it (so a
// failed delete never orphans live data); image cleanup is best-effort.
func (s *Service) DeleteAccount(ctx context.Context, userID string, password string) error {
	if strings.TrimSpace(userID) == "" {
		return ValidationError("userID", "userID is required")
	}
	if strings.TrimSpace(password) == "" {
		return ValidationError("password", "password is required")
	}

	_, passwordHash, err := s.repo.GetUserByID(ctx, userID)
	if errors.Is(err, ports.ErrNotFound) {
		return NotFound("user not found")
	}
	if err != nil {
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(password)) != nil {
		return Unauthorized("password is incorrect")
	}

	var imageKeys []string
	if s.imageGC != nil {
		imageKeys = s.imageGC.CollectOwnedImageKeys(ctx, userID)
	}

	if err := s.repo.DeleteUser(ctx, userID); err != nil {
		if errors.Is(err, ports.ErrNotFound) {
			return NotFound("user not found")
		}
		return err
	}

	if s.imageGC != nil {
		if s.imageGCAsync {
			detached := context.WithoutCancel(ctx)
			go s.imageGC.DeleteObjects(detached, imageKeys)
		} else {
			s.imageGC.DeleteObjects(ctx, imageKeys)
		}
	}
	return nil
}

func (s *Service) normalizeCreateInput(input *SignUpInput) (ports.CreateUserParams, error) {
	email := normalizeEmail(input.Email)
	if email == "" {
		return ports.CreateUserParams{}, ValidationError("email", "email is required")
	}
	fullName := strings.TrimSpace(input.FullName)
	if fullName == "" {
		return ports.CreateUserParams{}, ValidationError("fullName", "full name is required")
	}
	if strings.TrimSpace(input.Password) == "" {
		return ports.CreateUserParams{}, ValidationError("password", "password is required")
	}

	passwordHash, err := hashPassword(input.Password)
	if err != nil {
		return ports.CreateUserParams{}, err
	}

	return ports.CreateUserParams{
		Email:                 email,
		FullName:              fullName,
		Birthday:              utcOrNil(input.Birthday),
		Gender:                normalizeGender(input.Gender),
		PasswordHash:          passwordHash,
		PreferredCurrencyCode: normalizeCurrencyCode(input.PreferredCurrencyCode),
		NotificationsEnabled:  input.NotificationsEnabled,
		ReminderDays:          normalizeReminderDays(input.ReminderDays),
	}, nil
}

func normalizeGender(raw *string) *string {
	if raw == nil {
		return nil
	}

	normalized := strings.ToLower(strings.TrimSpace(*raw))
	switch normalized {
	case "":
		return nil
	case "man", "woman":
		return &normalized
	default:
		return nil
	}
}

func (s *Service) createSession(ctx context.Context, userID string) (string, error) {
	token, err := randomToken()
	if err != nil {
		return "", err
	}

	now := s.nowFn().UTC()
	err = s.repo.CreateSession(ctx, ports.CreateSessionParams{
		UserID:     userID,
		TokenHash:  tokenHash(token),
		ExpiresAt:  now.Add(sessionDuration),
		LastSeenAt: now,
	})
	if err != nil {
		return "", err
	}

	return token, nil
}

// utcOrNil normalizes an optional birthday to UTC, preserving nil (no birthday).
func utcOrNil(t *time.Time) *time.Time {
	if t == nil {
		return nil
	}
	utc := t.UTC()
	return &utc
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

func normalizeCurrencyCode(code string) string {
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" {
		return "USD"
	}
	return code
}

func normalizeReminderDays(days int) int {
	if days <= 0 {
		return 14
	}
	return days
}

func hashPassword(password string) (string, error) {
	hashed, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hashed), nil
}

func randomToken() (string, error) {
	return randhex.String(32)
}

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
