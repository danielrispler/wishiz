package postgres

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) List(ctx context.Context) ([]domain.Wishlist, error) {
	_ = ctx
	_ = r.pool
	return nil, nil
}

func (r *Repository) Create(ctx context.Context, title string, description string, year int) (domain.Wishlist, error) {
	_ = ctx
	_, _, _ = title, description, year
	_ = r.pool
	return domain.Wishlist{}, nil
}
