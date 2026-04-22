package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
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

func (r *Repository) List(ctx context.Context, requestUserID string) ([]domain.Wishlist, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			share_token,
			created_at,
			updated_at,
			is_archived
		FROM wishlists
		WHERE owner_id = $1::uuid
			OR id IN (
				SELECT wishlist_id FROM wishlist_members WHERE user_id = $1::uuid
			)
		ORDER BY updated_at DESC, created_at DESC
	`, requestUserID)
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

	if err := r.attachItems(ctx, indexByID, wishlists, requestUserID); err != nil {
		return nil, err
	}
	if err := r.attachMembers(ctx, indexByID, wishlists, requestUserID); err != nil {
		return nil, err
	}
	if err := r.attachInvites(ctx, indexByID, wishlists, requestUserID); err != nil {
		return nil, err
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
			share_token,
			created_at,
			updated_at,
			is_archived
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

	members, err := r.listMembersByWishlistID(ctx, r.pool, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	wishlist.Members = members

	invites, err := r.listInvitesByWishlistID(ctx, r.pool, id)
	if err != nil {
		return domain.Wishlist{}, err
	}
	wishlist.Invites = invites

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
			share_token
		)
		VALUES ($1::uuid, $2, $3, $4, $5, encode(gen_random_bytes(16), 'hex'))
		RETURNING
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			share_token,
			created_at,
			updated_at,
			is_archived
	`, params.OwnerID, params.Title, params.Description, params.Year, params.CoverImageURL)

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
			cover_image_url = $5
		WHERE id = $1::uuid
		RETURNING
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			share_token,
			created_at,
			updated_at,
			is_archived
	`, params.ID, params.Title, params.Description, params.Year, params.CoverImageURL)

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
			purchased_at = $11
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
				SET rank = $3
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

func (r *Repository) CreateInvite(ctx context.Context, params ports.CreateInviteParams) (domain.WishlistInvite, error) {
	row := r.pool.QueryRow(ctx, `
		INSERT INTO wishlist_invites (
			wishlist_id,
			email,
			role,
			invited_by_user_id,
			token_hash,
			expires_at
		)
		VALUES ($1::uuid, $2, $3, $4::uuid, $5, $6)
		ON CONFLICT (wishlist_id, email) DO UPDATE
		SET
			role = EXCLUDED.role,
			invited_by_user_id = EXCLUDED.invited_by_user_id,
			token_hash = EXCLUDED.token_hash,
			accepted_at = NULL,
			expires_at = EXCLUDED.expires_at
		RETURNING
			id::text,
			wishlist_id::text,
			email::text,
			role,
			invited_by_user_id::text,
			accepted_at,
			expires_at,
			created_at,
			updated_at
	`, params.WishlistID, params.Email, params.Role, params.InvitedByUserID, params.TokenHash, params.ExpiresAt)

	invite, err := scanInvite(row)
	if isForeignKeyViolation(err) {
		return domain.WishlistInvite{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.WishlistInvite{}, fmt.Errorf("create invite for wishlist %s: %w", params.WishlistID, err)
	}

	return invite, nil
}

func (r *Repository) DeleteInvite(ctx context.Context, wishlistID string, inviteID string) error {
	commandTag, err := r.pool.Exec(ctx, `
		DELETE FROM wishlist_invites
		WHERE wishlist_id = $1::uuid AND id = $2::uuid
	`, wishlistID, inviteID)
	if err != nil {
		return fmt.Errorf("delete invite %s from wishlist %s: %w", inviteID, wishlistID, err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}

	return nil
}

func (r *Repository) GetInviteByTokenHash(ctx context.Context, wishlistID string, tokenHash string) (domain.WishlistInvite, error) {
	row := r.pool.QueryRow(ctx, `
		SELECT
			id::text,
			wishlist_id::text,
			email::text,
			role,
			invited_by_user_id::text,
			accepted_at,
			expires_at,
			created_at,
			updated_at
		FROM wishlist_invites
		WHERE wishlist_id = $1::uuid AND token_hash = $2
	`, wishlistID, tokenHash)

	invite, err := scanInvite(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.WishlistInvite{}, ports.ErrNotFound
	}
	if err != nil {
		return domain.WishlistInvite{}, fmt.Errorf("get invite by token for wishlist %s: %w", wishlistID, err)
	}
	return invite, nil
}

func (r *Repository) AcceptInvite(ctx context.Context, params ports.AcceptInviteParams) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("begin accept invite transaction: %w", err)
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	commandTag, err := tx.Exec(ctx, `
		UPDATE wishlist_invites
		SET accepted_at = $3
		WHERE id = $1::uuid AND wishlist_id = $2::uuid
	`, params.InviteID, params.WishlistID, params.AcceptedAt)
	if err != nil {
		return fmt.Errorf("mark invite %s accepted: %w", params.InviteID, err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO wishlist_members (
			wishlist_id,
			user_id,
			role
		)
		VALUES ($1::uuid, $2::uuid, $3)
		ON CONFLICT (wishlist_id, user_id) DO UPDATE
		SET role = EXCLUDED.role
	`, params.WishlistID, params.UserID, params.Role)
	if isForeignKeyViolation(err) {
		return ports.ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("add member %s to wishlist %s: %w", params.UserID, params.WishlistID, err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit accept invite %s: %w", params.InviteID, err)
	}

	return nil
}

func (r *Repository) AddMember(ctx context.Context, wishlistID string, userID string, role string) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO wishlist_members (
			wishlist_id,
			user_id,
			role
		)
		VALUES ($1::uuid, $2::uuid, $3)
		ON CONFLICT (wishlist_id, user_id) DO UPDATE
		SET role = EXCLUDED.role
	`, wishlistID, userID, role)
	if isForeignKeyViolation(err) {
		return ports.ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("add member %s to wishlist %s: %w", userID, wishlistID, err)
	}

	return nil
}

func (r *Repository) RemoveMember(ctx context.Context, wishlistID string, userID string) error {
	commandTag, err := r.pool.Exec(ctx, `
		DELETE FROM wishlist_members
		WHERE wishlist_id = $1::uuid AND user_id = $2::uuid
	`, wishlistID, userID)
	if err != nil {
		return fmt.Errorf("remove member %s from wishlist %s: %w", userID, wishlistID, err)
	}
	if commandTag.RowsAffected() == 0 {
		return ports.ErrNotFound
	}

	return nil
}

func (r *Repository) setArchivedState(ctx context.Context, id string, archived bool) (domain.Wishlist, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE wishlists
		SET is_archived = $2
		WHERE id = $1::uuid
		RETURNING
			id::text,
			owner_id::text,
			title,
			description,
			year,
			cover_image_url,
			share_token,
			created_at,
			updated_at,
			is_archived
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

func (r *Repository) attachItems(ctx context.Context, indexByID map[string]int, wishlists []domain.Wishlist, requestUserID string) error {
	rows, err := r.pool.Query(ctx, `
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
		WHERE w.owner_id = $1::uuid
			OR w.id IN (
				SELECT wishlist_id FROM wishlist_members WHERE user_id = $1::uuid
			)
		ORDER BY i.wishlist_id, i.rank ASC
	`, requestUserID)
	if err != nil {
		return fmt.Errorf("list wishlist items: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		wishlistID, item, scanErr := scanWishlistItem(rows)
		if scanErr != nil {
			return scanErr
		}

		index, ok := indexByID[wishlistID]
		if !ok {
			continue
		}

		wishlists[index].Items = append(wishlists[index].Items, item)
	}
	if err = rows.Err(); err != nil {
		return fmt.Errorf("iterate wishlist items: %w", err)
	}

	return nil
}

func (r *Repository) attachMembers(ctx context.Context, indexByID map[string]int, wishlists []domain.Wishlist, requestUserID string) error {
	rows, err := r.pool.Query(ctx, `
		SELECT
			m.wishlist_id::text,
			m.user_id::text,
			u.email::text,
			u.full_name,
			m.role,
			m.created_at,
			m.updated_at
		FROM wishlist_members m
		JOIN app_users u ON u.id = m.user_id
		JOIN wishlists w ON w.id = m.wishlist_id
		WHERE w.owner_id = $1::uuid
			OR w.id IN (
				SELECT wishlist_id FROM wishlist_members WHERE user_id = $1::uuid
			)
		ORDER BY m.wishlist_id, m.created_at ASC
	`, requestUserID)
	if err != nil {
		return fmt.Errorf("list wishlist members: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		member, scanErr := scanMember(rows)
		if scanErr != nil {
			return scanErr
		}

		index, ok := indexByID[member.WishlistID]
		if !ok {
			continue
		}

		wishlists[index].Members = append(wishlists[index].Members, member)
	}
	if err = rows.Err(); err != nil {
		return fmt.Errorf("iterate wishlist members: %w", err)
	}

	return nil
}

func (r *Repository) attachInvites(ctx context.Context, indexByID map[string]int, wishlists []domain.Wishlist, requestUserID string) error {
	rows, err := r.pool.Query(ctx, `
		SELECT
			i.id::text,
			i.wishlist_id::text,
			i.email::text,
			i.role,
			i.invited_by_user_id::text,
			i.accepted_at,
			i.expires_at,
			i.created_at,
			i.updated_at
		FROM wishlist_invites i
		JOIN wishlists w ON w.id = i.wishlist_id
		WHERE w.owner_id = $1::uuid
			OR w.id IN (
				SELECT wishlist_id FROM wishlist_members WHERE user_id = $1::uuid
			)
		ORDER BY i.wishlist_id, i.created_at ASC
	`, requestUserID)
	if err != nil {
		return fmt.Errorf("list wishlist invites: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		invite, scanErr := scanInvite(rows)
		if scanErr != nil {
			return scanErr
		}

		index, ok := indexByID[invite.WishlistID]
		if !ok {
			continue
		}

		wishlists[index].Invites = append(wishlists[index].Invites, invite)
	}
	if err = rows.Err(); err != nil {
		return fmt.Errorf("iterate wishlist invites: %w", err)
	}

	return nil
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

func (r *Repository) listMembersByWishlistID(ctx context.Context, querier rowQueryer, wishlistID string) ([]domain.WishlistMember, error) {
	rows, err := querier.Query(ctx, `
		SELECT
			m.wishlist_id::text,
			m.user_id::text,
			u.email::text,
			u.full_name,
			m.role,
			m.created_at,
			m.updated_at
		FROM wishlist_members m
		JOIN app_users u ON u.id = m.user_id
		WHERE m.wishlist_id = $1::uuid
		ORDER BY m.created_at ASC
	`, wishlistID)
	if err != nil {
		return nil, fmt.Errorf("list members for wishlist %s: %w", wishlistID, err)
	}
	defer rows.Close()

	members := make([]domain.WishlistMember, 0)
	for rows.Next() {
		member, err := scanMember(rows)
		if err != nil {
			return nil, err
		}
		members = append(members, member)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate members for wishlist %s: %w", wishlistID, err)
	}

	return members, nil
}

func (r *Repository) listInvitesByWishlistID(ctx context.Context, querier rowQueryer, wishlistID string) ([]domain.WishlistInvite, error) {
	rows, err := querier.Query(ctx, `
		SELECT
			id::text,
			wishlist_id::text,
			email::text,
			role,
			invited_by_user_id::text,
			accepted_at,
			expires_at,
			created_at,
			updated_at
		FROM wishlist_invites
		WHERE wishlist_id = $1::uuid
		ORDER BY created_at ASC
	`, wishlistID)
	if err != nil {
		return nil, fmt.Errorf("list invites for wishlist %s: %w", wishlistID, err)
	}
	defer rows.Close()

	invites := make([]domain.WishlistInvite, 0)
	for rows.Next() {
		invite, err := scanInvite(rows)
		if err != nil {
			return nil, err
		}
		invites = append(invites, invite)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate invites for wishlist %s: %w", wishlistID, err)
	}

	return invites, nil
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
		&wishlist.ShareToken,
		&wishlist.CreatedAt,
		&wishlist.UpdatedAt,
		&wishlist.IsArchived,
	)
	if err != nil {
		return domain.Wishlist{}, err
	}

	wishlist.Members = []domain.WishlistMember{}
	wishlist.Invites = []domain.WishlistInvite{}
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

func scanMember(row interface{ Scan(...any) error }) (domain.WishlistMember, error) {
	var member domain.WishlistMember

	err := row.Scan(
		&member.WishlistID,
		&member.UserID,
		&member.Email,
		&member.FullName,
		&member.Role,
		&member.CreatedAt,
		&member.UpdatedAt,
	)
	if err != nil {
		return domain.WishlistMember{}, err
	}

	return member, nil
}

func scanInvite(row interface{ Scan(...any) error }) (domain.WishlistInvite, error) {
	var invite domain.WishlistInvite

	err := row.Scan(
		&invite.ID,
		&invite.WishlistID,
		&invite.Email,
		&invite.Role,
		&invite.InvitedByUserID,
		&invite.AcceptedAt,
		&invite.ExpiresAt,
		&invite.CreatedAt,
		&invite.UpdatedAt,
	)
	if err != nil {
		return domain.WishlistInvite{}, err
	}

	return invite, nil
}

func isForeignKeyViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23503"
}
