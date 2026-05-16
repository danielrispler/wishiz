package ports

import (
	"context"
	"errors"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
)

var (
	ErrNotFound      = errors.New("auth repository: not found")
	ErrEmailConflict = errors.New("auth repository: email conflict")
)

type Repository interface {
	CreateUser(ctx context.Context, params CreateUserParams) (domain.User, error)
	GetUserByEmail(ctx context.Context, email string) (domain.User, string, error)
	GetUserByID(ctx context.Context, id string) (domain.User, string, error)
	UpdateUser(ctx context.Context, params UpdateUserParams) (domain.User, error)
	UpdateUserPreferences(ctx context.Context, userID string, brands []string) (domain.User, error)
	CreateSession(ctx context.Context, params CreateSessionParams) error
	GetUserBySessionTokenHash(ctx context.Context, tokenHash string) (domain.User, error)
	DeleteSessionByTokenHash(ctx context.Context, tokenHash string) error
}

type CreateUserParams struct {
	Email                 string
	FullName              string
	Birthday              time.Time
	PasswordHash          string
	PreferredCurrencyCode string
	NotificationsEnabled  bool
	ReminderDays          int
}

type UpdateUserParams struct {
	ID                    string
	Email                 string
	FullName              string
	Birthday              time.Time
	PasswordHash          string
	PreferredCurrencyCode string
	NotificationsEnabled  bool
	ReminderDays          int
	PreferredBrands       []string
}

type CreateSessionParams struct {
	UserID     string
	TokenHash  string
	ExpiresAt  time.Time
	LastSeenAt time.Time
}
