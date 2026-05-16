package application

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/ports"
)

const sessionDuration = 30 * 24 * time.Hour

type Service struct {
	repo  ports.Repository
	nowFn func() time.Time
}

func NewService(repo ports.Repository) *Service {
	return &Service{
		repo:  repo,
		nowFn: time.Now,
	}
}

type SignUpInput struct {
	Email                 string
	Password              string
	FullName              string
	Birthday              time.Time
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
	Birthday              time.Time
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
	if input.Birthday.IsZero() {
		return domain.User{}, ValidationError("birthday", "birthday is required")
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
		Birthday:              input.Birthday.UTC(),
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

func (s *Service) SavePreferences(ctx context.Context, userID string, rawBrands []string) (domain.User, error) {
	if strings.TrimSpace(userID) == "" {
		return domain.User{}, ValidationError("userID", "userID is required")
	}
	brands, err := parseBrands(rawBrands)
	if err != nil {
		return domain.User{}, err
	}
	user, err := s.repo.UpdateUserPreferences(ctx, userID, brands)
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

func (s *Service) normalizeCreateInput(input *SignUpInput) (ports.CreateUserParams, error) {
	email := normalizeEmail(input.Email)
	if email == "" {
		return ports.CreateUserParams{}, ValidationError("email", "email is required")
	}
	fullName := strings.TrimSpace(input.FullName)
	if fullName == "" {
		return ports.CreateUserParams{}, ValidationError("fullName", "full name is required")
	}
	if input.Birthday.IsZero() {
		return ports.CreateUserParams{}, ValidationError("birthday", "birthday is required")
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
		Birthday:              input.Birthday.UTC(),
		PasswordHash:          passwordHash,
		PreferredCurrencyCode: normalizeCurrencyCode(input.PreferredCurrencyCode),
		NotificationsEnabled:  input.NotificationsEnabled,
		ReminderDays:          normalizeReminderDays(input.ReminderDays),
	}, nil
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
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}

func tokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
