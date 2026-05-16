package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/auth/ports"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) CreateUser(ctx context.Context, params ports.CreateUserParams) (domain.User, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO app_users (
			email,
			full_name,
			birthday,
			password_hash,
			preferred_currency_code,
			notifications_enabled,
			reminder_days
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING
			id::text,
			email,
			full_name,
			birthday,
			preferred_currency_code,
			notifications_enabled,
			reminder_days,
			onboarding_categories,
			preferred_brands,
			created_at,
			updated_at
	`, params.Email, params.FullName, params.Birthday, params.PasswordHash, params.PreferredCurrencyCode, params.NotificationsEnabled, params.ReminderDays)

	user, err := scanUser(row)
	if isUniqueViolation(err) {
		return domain.User{}, ports.ErrEmailConflict
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("create user: %w", err)
	}
	return user, nil
}

func (r *Repository) GetUserByEmail(ctx context.Context, email string) (domain.User, string, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT
			id::text,
			email,
			full_name,
			birthday,
			preferred_currency_code,
			notifications_enabled,
			reminder_days,
			onboarding_categories,
			preferred_brands,
			created_at,
			updated_at,
			password_hash
		FROM app_users
		WHERE email = $1
	`, email)

	user, passwordHash, err := scanUserWithPasswordHash(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, "", ports.ErrNotFound
	}
	if err != nil {
		return domain.User{}, "", fmt.Errorf("get user by email %s: %w", email, err)
	}
	return user, passwordHash, nil
}

func (r *Repository) GetUserByID(ctx context.Context, id string) (domain.User, string, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT
			id::text,
			email,
			full_name,
			birthday,
			preferred_currency_code,
			notifications_enabled,
			reminder_days,
			onboarding_categories,
			preferred_brands,
			created_at,
			updated_at,
			password_hash
		FROM app_users
		WHERE id = $1::uuid
	`, id)

	user, passwordHash, err := scanUserWithPasswordHash(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, "", ports.ErrNotFound
	}
	if err != nil {
		return domain.User{}, "", fmt.Errorf("get user by id %s: %w", id, err)
	}
	return user, passwordHash, nil
}

func (r *Repository) UpdateUser(ctx context.Context, params ports.UpdateUserParams) (domain.User, error) {
	rawCats := preferencesToStrings(params.OnboardingCategories)
	rawBrands := params.PreferredBrands
	if rawBrands == nil {
		rawBrands = []string{}
	}
	row := r.pool.QueryRow(ctx, `
		UPDATE app_users
		SET
			email = $2,
			full_name = $3,
			birthday = $4,
			password_hash = $5,
			preferred_currency_code = $6,
			notifications_enabled = $7,
			reminder_days = $8,
			onboarding_categories = $9,
			preferred_brands = $10,
			updated_at = NOW()
		WHERE id = $1::uuid
		RETURNING
			id::text,
			email,
			full_name,
			birthday,
			preferred_currency_code,
			notifications_enabled,
			reminder_days,
			onboarding_categories,
			preferred_brands,
			created_at,
			updated_at
	`, params.ID, params.Email, params.FullName, params.Birthday, params.PasswordHash,
		params.PreferredCurrencyCode, params.NotificationsEnabled, params.ReminderDays, rawCats, rawBrands)

	user, err := scanUser(row)
	if isUniqueViolation(err) {
		return domain.User{}, ports.ErrEmailConflict
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("update user %s: %w", params.ID, err)
	}
	return user, nil
}

func (r *Repository) UpdateUserPreferences(ctx context.Context, userID string, categories []domain.Preference, brands []string) (domain.User, error) {
	rawCats := preferencesToStrings(categories)
	if brands == nil {
		brands = []string{}
	}
	row := r.pool.QueryRow(ctx, `
		UPDATE app_users
		SET onboarding_categories = $2, preferred_brands = $3, updated_at = NOW()
		WHERE id = $1::uuid
		RETURNING
			id::text,
			email,
			full_name,
			birthday,
			preferred_currency_code,
			notifications_enabled,
			reminder_days,
			onboarding_categories,
			preferred_brands,
			created_at,
			updated_at
	`, userID, rawCats, brands)

	user, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("update preferences for user %s: %w", userID, err)
	}
	return user, nil
}

func (r *Repository) CreateSession(ctx context.Context, params ports.CreateSessionParams) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO app_sessions (
			user_id,
			token_hash,
			expires_at,
			last_seen_at
		)
		VALUES ($1::uuid, $2, $3, $4)
	`, params.UserID, params.TokenHash, params.ExpiresAt, params.LastSeenAt)
	if err != nil {
		return fmt.Errorf("create session for user %s: %w", params.UserID, err)
	}
	return nil
}

func (r *Repository) GetUserBySessionTokenHash(ctx context.Context, tokenHash string) (domain.User, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT
			u.id::text,
			u.email,
			u.full_name,
			u.birthday,
			u.preferred_currency_code,
			u.notifications_enabled,
			u.reminder_days,
			u.onboarding_categories,
			u.preferred_brands,
			u.created_at,
			u.updated_at
		FROM app_sessions s
		JOIN app_users u ON u.id = s.user_id
		WHERE s.token_hash = $1
			AND s.expires_at > NOW()
	`, tokenHash)

	user, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("get user by session token: %w", err)
	}
	return user, nil
}

func (r *Repository) DeleteSessionByTokenHash(ctx context.Context, tokenHash string) error {
	commandTag, err := r.pool.Exec(ctx, `
		DELETE FROM app_sessions
		WHERE token_hash = $1
	`, tokenHash)
	if err != nil {
		return fmt.Errorf("delete session: %w", err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}
	return nil
}

func scanUser(row interface{ Scan(...any) error }) (domain.User, error) {
	var user domain.User
	var rawCategories []string
	var rawBrands []string
	err := row.Scan(
		&user.ID,
		&user.Email,
		&user.FullName,
		&user.Birthday,
		&user.PreferredCurrencyCode,
		&user.NotificationsEnabled,
		&user.ReminderDays,
		&rawCategories,
		&rawBrands,
		&user.CreatedAt,
		&user.UpdatedAt,
	)
	if err != nil {
		return domain.User{}, err
	}
	user.OnboardingCategories = stringsToPreferences(rawCategories)
	user.PreferredBrands = rawBrands
	if user.PreferredBrands == nil {
		user.PreferredBrands = []string{}
	}
	return user, nil
}

func scanUserWithPasswordHash(row interface{ Scan(...any) error }) (domain.User, string, error) {
	var user domain.User
	var rawCategories []string
	var rawBrands []string
	var passwordHash string
	err := row.Scan(
		&user.ID,
		&user.Email,
		&user.FullName,
		&user.Birthday,
		&user.PreferredCurrencyCode,
		&user.NotificationsEnabled,
		&user.ReminderDays,
		&rawCategories,
		&rawBrands,
		&user.CreatedAt,
		&user.UpdatedAt,
		&passwordHash,
	)
	if err != nil {
		return domain.User{}, "", err
	}
	user.OnboardingCategories = stringsToPreferences(rawCategories)
	user.PreferredBrands = rawBrands
	if user.PreferredBrands == nil {
		user.PreferredBrands = []string{}
	}
	return user, passwordHash, nil
}

func preferencesToStrings(prefs []domain.Preference) []string {
	if len(prefs) == 0 {
		return []string{}
	}
	raw := make([]string, len(prefs))
	for i, p := range prefs {
		raw[i] = string(p)
	}
	return raw
}

func stringsToPreferences(raw []string) []domain.Preference {
	prefs := make([]domain.Preference, len(raw))
	for i, s := range raw {
		prefs[i] = domain.Preference(s)
	}
	return prefs
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
