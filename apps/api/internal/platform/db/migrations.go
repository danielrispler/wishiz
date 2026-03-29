package db

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.up.sql
var migrationFiles embed.FS

func RunMigrations(ctx context.Context, pool *pgxpool.Pool) error {
	if _, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`); err != nil {
		return fmt.Errorf("ensure schema_migrations table: %w", err)
	}

	entries, err := fs.Glob(migrationFiles, "migrations/*.up.sql")
	if err != nil {
		return fmt.Errorf("list migrations: %w", err)
	}

	sort.Strings(entries)

	for _, entry := range entries {
		applied, err := migrationApplied(ctx, pool, entry)
		if err != nil {
			return err
		}
		if applied {
			continue
		}

		source, err := migrationFiles.ReadFile(entry)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", entry, err)
		}

		tx, err := pool.Begin(ctx)
		if err != nil {
			return fmt.Errorf("begin migration transaction for %s: %w", entry, err)
		}

		if _, err := tx.Exec(ctx, string(source)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("apply migration %s: %w", entry, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, entry); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("record migration %s: %w", entry, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("commit migration %s: %w", entry, err)
		}
	}

	return nil
}

func migrationApplied(ctx context.Context, pool *pgxpool.Pool, version string) (bool, error) {
	var exists bool

	if err := pool.QueryRow(
		ctx,
		`SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`,
		version,
	).Scan(&exists); err != nil {
		return false, fmt.Errorf("check migration %s: %w", version, err)
	}

	return exists, nil
}
