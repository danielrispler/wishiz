package db

import (
	"testing"

	"github.com/jackc/pgx/v5"
)

const testDSN = "postgres://user:pass@localhost:5432/wishiz?sslmode=disable"

// The pool must be safe over the Supabase transaction pooler: unnamed
// extended-protocol statements (QueryExecModeExec) and no statement/description
// caches, or PgBouncer reuses a prepared statement across the wrong connection.
func TestPoolConfigIsTransactionPoolerSafe(t *testing.T) {
	t.Parallel()

	cfg, err := poolConfig(testDSN, 7)
	if err != nil {
		t.Fatalf("poolConfig: %v", err)
	}

	if cfg.ConnConfig.DefaultQueryExecMode != pgx.QueryExecModeExec {
		t.Errorf("exec mode = %v, want QueryExecModeExec", cfg.ConnConfig.DefaultQueryExecMode)
	}
	if cfg.ConnConfig.StatementCacheCapacity != 0 {
		t.Errorf("statement cache = %d, want 0", cfg.ConnConfig.StatementCacheCapacity)
	}
	if cfg.ConnConfig.DescriptionCacheCapacity != 0 {
		t.Errorf("description cache = %d, want 0", cfg.ConnConfig.DescriptionCacheCapacity)
	}
	if cfg.MaxConns != 7 {
		t.Errorf("max conns = %d, want 7", cfg.MaxConns)
	}
	if cfg.MinConns != 0 {
		t.Errorf("min conns = %d, want 0 (scale-to-zero friendly)", cfg.MinConns)
	}
}

func TestPoolConfigDefaultsMaxConns(t *testing.T) {
	t.Parallel()

	cfg, err := poolConfig(testDSN, 0)
	if err != nil {
		t.Fatalf("poolConfig: %v", err)
	}
	if cfg.MaxConns != 5 {
		t.Errorf("max conns = %d, want default 5", cfg.MaxConns)
	}
}

// The migrate Job must use the simple protocol so its multi-statement DDL runs
// and stays PgBouncer-safe over the transaction pooler.
func TestSimpleConnConfigUsesSimpleProtocol(t *testing.T) {
	t.Parallel()

	cfg, err := simpleConnConfig(testDSN)
	if err != nil {
		t.Fatalf("simpleConnConfig: %v", err)
	}
	if cfg.DefaultQueryExecMode != pgx.QueryExecModeSimpleProtocol {
		t.Errorf("exec mode = %v, want QueryExecModeSimpleProtocol", cfg.DefaultQueryExecMode)
	}
}
