package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/ports"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) GetTrending(ctx context.Context, userID string, limit int) ([]domain.DiscoverProduct, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			p.id::text,
			p.title,
			p.brand,
			p.category,
			p.image_url,
			p.product_url,
			p.save_count,
			p.created_at,
			(dps.user_id IS NOT NULL) AS saved_by_user,
			p.price_label,
			p.gender,
			p.product_type
		FROM discover_products p
		LEFT JOIN discover_product_saves dps
			ON dps.product_id = p.id AND dps.user_id = $1::uuid
		ORDER BY p.save_count DESC, p.created_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, fmt.Errorf("get trending products: %w", err)
	}
	return collectProducts(rows)
}

func (r *Repository) GetForYou(ctx context.Context, userID string, brands []string, limit int) ([]domain.DiscoverProduct, error) {
	if len(brands) == 0 {
		return r.GetTrending(ctx, userID, limit)
	}
	rows, err := r.pool.Query(ctx, `
		SELECT
			p.id::text,
			p.title,
			p.brand,
			p.category,
			p.image_url,
			p.product_url,
			p.save_count,
			p.created_at,
			(dps.user_id IS NOT NULL) AS saved_by_user,
			p.price_label,
			p.gender,
			p.product_type
		FROM discover_products p
		LEFT JOIN discover_product_saves dps
			ON dps.product_id = p.id AND dps.user_id = $1::uuid
		WHERE p.brand = ANY($2::text[])
		ORDER BY RANDOM()
		LIMIT $3
	`, userID, brands, limit)
	if err != nil {
		return nil, fmt.Errorf("get for-you products: %w", err)
	}
	return collectProducts(rows)
}

func (r *Repository) GetStarterPacks(ctx context.Context, userID string) ([]domain.StarterPack, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id::text, title, subtitle, cover_image_url
		FROM starter_packs
		ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, fmt.Errorf("get starter packs: %w", err)
	}
	defer rows.Close()

	var packs []domain.StarterPack
	for rows.Next() {
		var p domain.StarterPack
		if err := rows.Scan(&p.ID, &p.Title, &p.Subtitle, &p.CoverImageURL); err != nil {
			return nil, fmt.Errorf("scan starter pack: %w", err)
		}
		packs = append(packs, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate starter packs: %w", err)
	}

	for i := range packs {
		items, previews, err := r.getPackItems(ctx, packs[i].ID, userID)
		if err != nil {
			return nil, err
		}
		packs[i].Items = items
		packs[i].ItemCount = len(items)
		packs[i].PreviewItems = previews
	}

	if packs == nil {
		packs = []domain.StarterPack{}
	}
	return packs, nil
}

func (r *Repository) getPackItems(ctx context.Context, packID, userID string) ([]domain.DiscoverProduct, []string, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			p.id::text,
			p.title,
			p.brand,
			p.category,
			p.image_url,
			p.product_url,
			p.save_count,
			p.created_at,
			(dps.user_id IS NOT NULL) AS saved_by_user,
			p.price_label,
			p.gender,
			p.product_type
		FROM starter_pack_items spi
		JOIN discover_products p ON p.id = spi.product_id
		LEFT JOIN discover_product_saves dps
			ON dps.product_id = p.id AND dps.user_id = $2::uuid
		WHERE spi.pack_id = $1::uuid
		ORDER BY spi.rank
	`, packID, userID)
	if err != nil {
		return nil, nil, fmt.Errorf("get pack items for pack %s: %w", packID, err)
	}
	items, err := collectProducts(rows)
	if err != nil {
		return nil, nil, err
	}

	previews := make([]string, 0, 3)
	for _, item := range items {
		if len(previews) >= 3 {
			break
		}
		previews = append(previews, item.ImageURL)
	}
	return items, previews, nil
}

func (r *Repository) ToggleSave(ctx context.Context, userID, productID string) (bool, int, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return false, 0, fmt.Errorf("begin toggle save tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var exists bool
	err = tx.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM discover_products WHERE id = $1::uuid
		)
	`, productID).Scan(&exists)
	if err != nil {
		return false, 0, fmt.Errorf("check product exists: %w", err)
	}
	if !exists {
		return false, 0, ports.ErrNotFound
	}

	tag, err := tx.Exec(ctx, `
		INSERT INTO discover_product_saves (user_id, product_id)
		VALUES ($1::uuid, $2::uuid)
		ON CONFLICT DO NOTHING
	`, userID, productID)
	if err != nil {
		return false, 0, fmt.Errorf("insert save: %w", err)
	}

	saved := tag.RowsAffected() > 0
	delta := 1
	if !saved {
		_, err = tx.Exec(ctx, `
			DELETE FROM discover_product_saves
			WHERE user_id = $1::uuid AND product_id = $2::uuid
		`, userID, productID)
		if err != nil {
			return false, 0, fmt.Errorf("delete save: %w", err)
		}
		delta = -1
	}

	var newCount int
	err = tx.QueryRow(ctx, `
		UPDATE discover_products
		SET save_count = GREATEST(0, save_count + $2)
		WHERE id = $1::uuid
		RETURNING save_count
	`, productID, delta).Scan(&newCount)
	if err != nil {
		return false, 0, fmt.Errorf("update save count: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return false, 0, fmt.Errorf("commit toggle save: %w", err)
	}
	return saved, newCount, nil
}

func (r *Repository) GrabStarterPack(ctx context.Context, userID, packID, wishlistID string) (int, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("begin grab pack tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var packExists bool
	err = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM starter_packs WHERE id = $1::uuid)`, packID).Scan(&packExists)
	if err != nil {
		return 0, fmt.Errorf("check pack exists: %w", err)
	}
	if !packExists {
		return 0, ports.ErrNotFound
	}

	var wishlistOwnerID string
	err = tx.QueryRow(ctx, `SELECT owner_id::text FROM wishlists WHERE id = $1::uuid AND is_archived = FALSE`, wishlistID).Scan(&wishlistOwnerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ports.ErrNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("check wishlist: %w", err)
	}
	if wishlistOwnerID != userID {
		return 0, ports.ErrNotFound
	}

	var maxRank int
	err = tx.QueryRow(ctx, `
		SELECT COALESCE(MAX(rank), 0) FROM wishlist_items WHERE wishlist_id = $1::uuid
	`, wishlistID).Scan(&maxRank)
	if err != nil {
		return 0, fmt.Errorf("get max rank: %w", err)
	}

	rows, err := tx.Query(ctx, `
		SELECT p.title, p.image_url, p.product_url
		FROM starter_pack_items spi
		JOIN discover_products p ON p.id = spi.product_id
		WHERE spi.pack_id = $1::uuid
		ORDER BY spi.rank
	`, packID)
	if err != nil {
		return 0, fmt.Errorf("fetch pack items: %w", err)
	}
	defer rows.Close()

	type packItem struct {
		title      string
		imageURL   string
		productURL *string
	}
	var items []packItem
	for rows.Next() {
		var it packItem
		if err := rows.Scan(&it.title, &it.imageURL, &it.productURL); err != nil {
			return 0, fmt.Errorf("scan pack item: %w", err)
		}
		items = append(items, it)
	}
	if err := rows.Err(); err != nil {
		return 0, fmt.Errorf("iterate pack items: %w", err)
	}

	for i, it := range items {
		_, err = tx.Exec(ctx, `
			INSERT INTO wishlist_items (wishlist_id, title, rank, image_url, price_label, product_url)
			VALUES ($1::uuid, $2, $3, $4, $5, $6)
		`, wishlistID, it.title, maxRank+i+1, it.imageURL, nil, it.productURL)
		if err != nil {
			return 0, fmt.Errorf("insert wishlist item: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("commit grab pack: %w", err)
	}
	return len(items), nil
}

func (r *Repository) SeedProduct(ctx context.Context, in ports.SeedProductInput) (domain.DiscoverProduct, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO discover_products (title, brand, category, image_url, product_url, price_label, gender, product_type)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (product_url) DO UPDATE
		SET
			title = EXCLUDED.title,
			brand = EXCLUDED.brand,
			category = EXCLUDED.category,
			image_url = EXCLUDED.image_url,
			price_label = EXCLUDED.price_label,
			gender = EXCLUDED.gender,
			product_type = EXCLUDED.product_type,
			updated_at = NOW()
		RETURNING
			id::text, title, brand, category, image_url, product_url, save_count, created_at,
			price_label, gender, product_type
	`, in.Title, in.Brand, in.Category, in.ImageURL, in.ProductURL, in.PriceLabel, in.Gender, in.ProductType)

	var p domain.DiscoverProduct
	err := row.Scan(&p.ID, &p.Title, &p.Brand, &p.Category, &p.ImageURL, &p.ProductURL, &p.SaveCount, &p.CreatedAt,
		&p.PriceLabel, &p.Gender, &p.ProductType)
	if err != nil {
		return domain.DiscoverProduct{}, fmt.Errorf("seed product: %w", err)
	}
	return p, nil
}

func (r *Repository) CreateStarterPack(ctx context.Context, title, subtitle, coverImageURL string, productIDs []string) (domain.StarterPack, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.StarterPack{}, fmt.Errorf("begin create pack tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var pack domain.StarterPack
	err = tx.QueryRow(ctx, `
		INSERT INTO starter_packs (title, subtitle, cover_image_url)
		VALUES ($1, $2, $3)
		RETURNING id::text, title, subtitle, cover_image_url
	`, title, subtitle, coverImageURL).Scan(&pack.ID, &pack.Title, &pack.Subtitle, &pack.CoverImageURL)
	if err != nil {
		return domain.StarterPack{}, fmt.Errorf("insert starter pack: %w", err)
	}

	for i, pid := range productIDs {
		_, err = tx.Exec(ctx, `
			INSERT INTO starter_pack_items (pack_id, product_id, rank)
			VALUES ($1::uuid, $2::uuid, $3)
		`, pack.ID, pid, i+1)
		if err != nil {
			return domain.StarterPack{}, fmt.Errorf("insert pack item %s: %w", pid, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.StarterPack{}, fmt.Errorf("commit create pack: %w", err)
	}

	pack.ItemCount = len(productIDs)
	return pack, nil
}

func collectProducts(rows pgx.Rows) ([]domain.DiscoverProduct, error) {
	defer rows.Close()
	var products []domain.DiscoverProduct
	for rows.Next() {
		var p domain.DiscoverProduct
		if err := rows.Scan(
			&p.ID, &p.Title, &p.Brand, &p.Category,
			&p.ImageURL, &p.ProductURL,
			&p.SaveCount, &p.CreatedAt, &p.SavedByUser,
			&p.PriceLabel, &p.Gender, &p.ProductType,
		); err != nil {
			return nil, fmt.Errorf("scan discover product: %w", err)
		}
		products = append(products, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate discover products: %w", err)
	}
	if products == nil {
		products = []domain.DiscoverProduct{}
	}
	return products, nil
}
