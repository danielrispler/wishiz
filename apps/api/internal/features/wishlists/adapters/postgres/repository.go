package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/ports"
)

type Repository struct {
	pool *pgxpool.Pool
}

type rowQueryer interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) List(ctx context.Context, requestUserID string, requestUserEmail string) ([]domain.Wishlist, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			created_at,
			updated_at,
			is_archived,
			is_shared
		FROM wishlists
		WHERE owner_id = $1::uuid OR (
			is_shared = true AND id IN (
			SELECT wishlist_id FROM wishlist_shared_users WHERE email = $2
			)
		)
		ORDER BY updated_at DESC, created_at DESC
	`, requestUserID, requestUserEmail)
	if err != nil {
		return nil, fmt.Errorf("list wishlists: %w", err)
	}
	defer rows.Close()

	wishlists := make([]domain.Wishlist, 0)
	indexByID := make(map[string]int)

	for rows.Next() {
		wishlist, scanErr := scanWishlist(rows)
		if scanErr != nil {
			return nil, scanErr
		}

		indexByID[wishlist.ID] = len(wishlists)
		wishlists = append(wishlists, wishlist)
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate wishlists: %w", err)
	}
	if len(wishlists) == 0 {
		return []domain.Wishlist{}, nil
	}

	itemRows, err := r.pool.Query(ctx, `
		SELECT
			i.id::text,
			i.wishlist_id::text,
			i.title,
			i.rank,
			i.notes,
			i.price_label,
			i.priority,
			i.status,
			i.image_url,
			i.product_url,
			i.purchased_at,
			i.created_at,
			i.updated_at
		FROM wishlist_items i
		JOIN wishlists w ON w.id = i.wishlist_id
		WHERE w.owner_id = $1::uuid OR (
			w.is_shared = true AND w.id IN (
				SELECT wishlist_id FROM wishlist_shared_users WHERE email = $2
			)
		)
		ORDER BY wishlist_id, rank ASC
	`, requestUserID, requestUserEmail)
	if err != nil {
		return nil, fmt.Errorf("list wishlist items: %w", err)
	}
	defer itemRows.Close()

	for itemRows.Next() {
		wishlistID, item, scanErr := scanWishlistItem(itemRows)
		if scanErr != nil {
			return nil, scanErr
		}

		index, ok := indexByID[wishlistID]
		if !ok {
			continue
		}

		wishlists[index].Items = append(wishlists[index].Items, item)
	}
	if err = itemRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate wishlist items: %w", err)
	}

	sharedUserRows, err := r.pool.Query(ctx, `
		SELECT
			su.wishlist_id::text,
			su.id::text,
			su.name,
			su.email,
			su.role
		FROM wishlist_shared_users su
		JOIN wishlists w ON w.id = su.wishlist_id
		WHERE w.owner_id = $1::uuid OR (
			w.is_shared = true AND w.id IN (
				SELECT wishlist_id FROM wishlist_shared_users WHERE email = $2
			)
		)
		ORDER BY wishlist_id, created_at ASC
	`, requestUserID, requestUserEmail)
	if err != nil {
		return nil, fmt.Errorf("list shared users: %w", err)
	}
	defer sharedUserRows.Close()

	for sharedUserRows.Next() {
		var wishlistID string
		var user domain.SharedUser
		if scanErr := sharedUserRows.Scan(&wishlistID, &user.ID, &user.Name, &user.Email, &user.Role); scanErr != nil {
			return nil, scanErr
		}

		index, ok := indexByID[wishlistID]
		if !ok {
			continue
		}

		wishlists[index].SharedUsers = append(wishlists[index].SharedUsers, user)
	}
	if err = sharedUserRows.Err(); err != nil {
		return nil, fmt.Errorf("iterate shared users: %w", err)
	}

	return wishlists, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (domain.Wishlist, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			created_at,
			updated_at,
			is_archived,
			is_shared
		FROM wishlists
		WHERE id = $1::uuid
	`, id)

	wishlist, err := scanWishlist(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Wishlist{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Wishlist{}, fmt.Errorf("get wishlist %s: %w", id, err)
	}

	items, err := r.listItemsByWishlistID(ctx, r.pool, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	wishlist.Items = items

	sharedUsers, err := r.listSharedUsersByWishlistID(ctx, r.pool, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	wishlist.SharedUsers = sharedUsers

	return wishlist, nil
}

func (r *Repository) Create(ctx context.Context, params ports.CreateWishlistParams) (domain.Wishlist, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO wishlists (
			owner_id,
			title,
			description,
			year,
			cover_image_url,
			is_shared
		)
		VALUES ($1::uuid, $2, $3, $4, $5, $6)
		RETURNING
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			created_at,
			updated_at,
			is_archived,
			is_shared
	`, params.OwnerID, params.Title, params.Description, params.Year, params.CoverImageURL, params.IsShared)

	wishlist, err := scanWishlist(row)
	if err != nil {
		return domain.Wishlist{}, fmt.Errorf("create wishlist: %w", err)
	}

	return wishlist, nil
}

func (r *Repository) Update(ctx context.Context, params ports.UpdateWishlistParams) (domain.Wishlist, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE wishlists
		SET
			title = $2,
			description = $3,
			year = $4,
			cover_image_url = $5,
			is_shared = $6,
			updated_at = NOW()
		WHERE id = $1::uuid
		RETURNING
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			created_at,
			updated_at,
			is_archived,
			is_shared
	`, params.ID, params.Title, params.Description, params.Year, params.CoverImageURL, params.IsShared)

	wishlist, err := scanWishlist(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Wishlist{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Wishlist{}, fmt.Errorf("update wishlist %s: %w", params.ID, err)
	}

	return wishlist, nil
}

func (r *Repository) Delete(ctx context.Context, id string) error {
	commandTag, err := r.pool.Exec(ctx, `DELETE FROM wishlists WHERE id = $1::uuid`, id)
	if err != nil {
		return fmt.Errorf("delete wishlist %s: %w", id, err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}

	return nil
}

func (r *Repository) Archive(ctx context.Context, id string) (domain.Wishlist, error) {
	return r.setArchivedState(ctx, id, true)
}

func (r *Repository) Restore(ctx context.Context, id string) (domain.Wishlist, error) {
	return r.setArchivedState(ctx, id, false)
}

func (r *Repository) AddItem(ctx context.Context, params ports.AddItemParams) (domain.WishlistItem, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return domain.WishlistItem{}, fmt.Errorf("begin add wishlist item transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	var lockedID string
	err = tx.QueryRow(
		ctx,
		`SELECT id::text FROM wishlists WHERE id = $1::uuid FOR UPDATE`,
		params.WishlistID,
	).Scan(&lockedID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.WishlistItem{}, ports.ErrNotFound
	} else if err != nil {
		return domain.WishlistItem{}, fmt.Errorf("lock wishlist %s before add item: %w", params.WishlistID, err)
	}

	var nextRank int
	err = tx.QueryRow(
		ctx,
		`SELECT COALESCE(MAX(rank), 0) + 1 FROM wishlist_items WHERE wishlist_id = $1::uuid`,
		params.WishlistID,
	).Scan(&nextRank)
	if err != nil {
		return domain.WishlistItem{}, fmt.Errorf("get next item rank for wishlist %s: %w", params.WishlistID, err)
	}

	row := tx.QueryRow(ctx, `
		INSERT INTO wishlist_items (
			wishlist_id,
			title,
			rank,
			notes,
			price_label,
			priority,
			status,
			image_url,
			product_url,
			purchased_at
		)
		VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING
			id::text,
			wishlist_id::text,
			title,
			rank,
			notes,
			price_label,
			priority,
			status,
			image_url,
			product_url,
			purchased_at,
			created_at,
			updated_at
	`, params.WishlistID, params.Title, nextRank, params.Notes, params.PriceLabel, params.Priority, params.Status, params.ImageURL, params.ProductURL, params.PurchasedAt)

	_, item, err := scanWishlistItem(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.WishlistItem{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.WishlistItem{}, fmt.Errorf("add item to wishlist %s: %w", params.WishlistID, err)
	}

	if _, err := tx.Exec(ctx, `UPDATE wishlists SET updated_at = NOW() WHERE id = $1::uuid`, params.WishlistID); err != nil {
		return domain.WishlistItem{}, fmt.Errorf("touch wishlist %s after add item: %w", params.WishlistID, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.WishlistItem{}, fmt.Errorf("commit add item for wishlist %s: %w", params.WishlistID, err)
	}

	return item, nil
}

func (r *Repository) UpdateItem(ctx context.Context, params ports.UpdateItemParams) (domain.WishlistItem, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return domain.WishlistItem{}, fmt.Errorf("begin update wishlist item transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	row := tx.QueryRow(ctx, `
		UPDATE wishlist_items
		SET
			title = $3,
			rank = $4,
			notes = $5,
			price_label = $6,
			priority = $7,
			status = $8,
			image_url = $9,
			product_url = $10,
			purchased_at = $11,
			updated_at = NOW()
		WHERE wishlist_id = $1::uuid
			AND id = $2::uuid
		RETURNING
			id::text,
			wishlist_id::text,
			title,
			rank,
			notes,
			price_label,
			priority,
			status,
			image_url,
			product_url,
			purchased_at,
			created_at,
			updated_at
	`, params.WishlistID, params.ItemID, params.Title, params.Rank, params.Notes, params.PriceLabel, params.Priority, params.Status, params.ImageURL, params.ProductURL, params.PurchasedAt)

	_, item, err := scanWishlistItem(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.WishlistItem{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.WishlistItem{}, fmt.Errorf("update item %s in wishlist %s: %w", params.ItemID, params.WishlistID, err)
	}

	if _, err := tx.Exec(ctx, `UPDATE wishlists SET updated_at = NOW() WHERE id = $1::uuid`, params.WishlistID); err != nil {
		return domain.WishlistItem{}, fmt.Errorf("touch wishlist %s after update item: %w", params.WishlistID, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return domain.WishlistItem{}, fmt.Errorf("commit update item %s in wishlist %s: %w", params.ItemID, params.WishlistID, err)
	}

	return item, nil
}

func (r *Repository) DeleteItem(ctx context.Context, wishlistID string, itemID string) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("begin delete wishlist item transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	commandTag, err := tx.Exec(
		ctx,
		`DELETE FROM wishlist_items WHERE wishlist_id = $1::uuid AND id = $2::uuid`,
		wishlistID,
		itemID,
	)
	if err != nil {
		return fmt.Errorf("delete item %s from wishlist %s: %w", itemID, wishlistID, err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}

	if _, err := tx.Exec(ctx, `UPDATE wishlists SET updated_at = NOW() WHERE id = $1::uuid`, wishlistID); err != nil {
		return fmt.Errorf("touch wishlist %s after delete item: %w", wishlistID, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit delete item %s from wishlist %s: %w", itemID, wishlistID, err)
	}

	return nil
}

func (r *Repository) ReorderItems(ctx context.Context, wishlistID string, orderedItemIDs []string) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("begin reorder items transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	var lockedID string
	if err := tx.QueryRow(
		ctx,
		`SELECT id::text FROM wishlists WHERE id = $1::uuid FOR UPDATE`,
		wishlistID,
	).Scan(&lockedID); errors.Is(err, pgx.ErrNoRows) {
		return ports.ErrNotFound
	} else if err != nil {
		return fmt.Errorf("lock wishlist %s for reorder: %w", wishlistID, err)
	}

	if _, err := tx.Exec(ctx, `SET CONSTRAINTS wishlist_items_wishlist_rank_unique DEFERRED`); err != nil {
		return fmt.Errorf("defer wishlist rank constraint for %s: %w", wishlistID, err)
	}

	for index, itemID := range orderedItemIDs {
		if _, err := tx.Exec(
			ctx,
			`
				UPDATE wishlist_items
				SET rank = $3, updated_at = NOW()
				WHERE wishlist_id = $1::uuid AND id = $2::uuid
			`,
			wishlistID,
			itemID,
			index+1,
		); err != nil {
			return fmt.Errorf("set rank for item %s in wishlist %s: %w", itemID, wishlistID, err)
		}
	}

	if _, err := tx.Exec(ctx, `UPDATE wishlists SET updated_at = NOW() WHERE id = $1::uuid`, wishlistID); err != nil {
		return fmt.Errorf("touch wishlist %s after reorder: %w", wishlistID, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit reorder items for wishlist %s: %w", wishlistID, err)
	}

	return nil
}

func (r *Repository) setArchivedState(ctx context.Context, id string, archived bool) (domain.Wishlist, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE wishlists
		SET
			is_archived = $2,
			updated_at = NOW()
		WHERE id = $1::uuid
		RETURNING
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			created_at,
			updated_at,
			is_archived,
			is_shared
	`, id, archived)

	wishlist, err := scanWishlist(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Wishlist{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.Wishlist{}, fmt.Errorf("set archive state for wishlist %s: %w", id, err)
	}

	return wishlist, nil
}

func (r *Repository) listItemsByWishlistID(ctx context.Context, querier rowQueryer, wishlistID string) ([]domain.WishlistItem, error) {
	rows, err := querier.Query(ctx, `
		SELECT
			id::text,
			wishlist_id::text,
			title,
			rank,
			notes,
			price_label,
			priority,
			status,
			image_url,
			product_url,
			purchased_at,
			created_at,
			updated_at
		FROM wishlist_items
		WHERE wishlist_id = $1::uuid
		ORDER BY rank ASC
	`, wishlistID)
	if err != nil {
		return nil, fmt.Errorf("list items for wishlist %s: %w", wishlistID, err)
	}
	defer rows.Close()

	items := make([]domain.WishlistItem, 0)
	for rows.Next() {
		_, item, err := scanWishlistItem(rows)
		if err != nil {
			return nil, err
		}

		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate items for wishlist %s: %w", wishlistID, err)
	}

	return items, nil
}

func scanWishlist(row interface{ Scan(...any) error }) (domain.Wishlist, error) {
	var wishlist domain.Wishlist

	err := row.Scan(
		&wishlist.ID,
		&wishlist.OwnerID,
		&wishlist.Title,
		&wishlist.Description,
		&wishlist.Year,
		&wishlist.CoverImageURL,
		&wishlist.CreatedAt,
		&wishlist.UpdatedAt,
		&wishlist.IsArchived,
		&wishlist.IsShared,
	)
	if err != nil {
		return domain.Wishlist{}, err
	}

	wishlist.SharedUsers = []domain.SharedUser{}
	wishlist.Items = []domain.WishlistItem{}

	return wishlist, nil
}

func scanWishlistItem(row interface{ Scan(...any) error }) (string, domain.WishlistItem, error) {
	var wishlistID string
	var item domain.WishlistItem

	err := row.Scan(
		&item.ID,
		&wishlistID,
		&item.Title,
		&item.Rank,
		&item.Notes,
		&item.PriceLabel,
		&item.Priority,
		&item.Status,
		&item.ImageURL,
		&item.ProductURL,
		&item.PurchasedAt,
		&item.CreatedAt,
		&item.UpdatedAt,
	)
	if err != nil {
		return "", domain.WishlistItem{}, err
	}

	return wishlistID, item, nil
}

func (r *Repository) listSharedUsersByWishlistID(ctx context.Context, querier rowQueryer, wishlistID string) ([]domain.SharedUser, error) {
	rows, err := querier.Query(ctx, `
		SELECT
			id::text,
			name,
			email,
			role
		FROM wishlist_shared_users
		WHERE wishlist_id = $1::uuid
		ORDER BY created_at ASC
	`, wishlistID)
	if err != nil {
		return nil, fmt.Errorf("list shared users for wishlist %s: %w", wishlistID, err)
	}
	defer rows.Close()

	users := make([]domain.SharedUser, 0)
	for rows.Next() {
		var user domain.SharedUser
		if err := rows.Scan(&user.ID, &user.Name, &user.Email, &user.Role); err != nil {
			return nil, err
		}
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate shared users for wishlist %s: %w", wishlistID, err)
	}

	return users, nil
}

func (r *Repository) AddSharedUser(ctx context.Context, wishlistID string, user domain.SharedUser) error {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO wishlist_shared_users (
			wishlist_id,
			name,
			email,
			role
		)
		VALUES ($1::uuid, $2, $3, $4)
		RETURNING id::text
	`, wishlistID, user.Name, user.Email, user.Role)

	var insertedID string
	err := row.Scan(&insertedID)
	if err != nil {
		return fmt.Errorf("add shared user to wishlist %s: %w", wishlistID, err)
	}

	return nil
}

func (r *Repository) RemoveSharedUser(ctx context.Context, wishlistID string, userID string) error {
	commandTag, err := r.pool.Exec(ctx, `
		DELETE FROM wishlist_shared_users
		WHERE wishlist_id = $1::uuid AND id = $2::uuid
	`, wishlistID, userID)
	if err != nil {
		return fmt.Errorf("remove shared user %s from wishlist %s: %w", userID, wishlistID, err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}

	return nil
}
