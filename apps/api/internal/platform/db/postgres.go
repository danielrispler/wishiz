package db

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect opens a tuned pgx pool. The tuning targets the Supabase transaction
// pooler (Supavisor / PgBouncer in transaction mode), where server-side prepared
// statements are NOT safe to reuse across pooled connections:
//   - QueryExecModeExec uses the unnamed extended-protocol statement per query
//     (parameterised + PgBouncer-safe), and the statement/description caches are
//     disabled so pgx never tries to reuse a named prepared statement.
//   - MinConns=0 keeps the pool scale-to-zero friendly; MaxConns is bounded so
//     Σ(instances × DB_MAX_CONNS) stays under the pooler's client cap.
//
// No-argument Exec calls still fall back to the simple protocol inside pgx, so
// multi-statement DDL (migrations) keeps working through this pool.
func Connect(ctx context.Context, databaseURL string, maxConns int) (*pgxpool.Pool, error) {
	config, err := poolConfig(databaseURL, maxConns)
	if err != nil {
		return nil, err
	}

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("create postgres pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping postgres: %w", err)
	}

	return pool, nil
}

// poolConfig builds the tuned pool config. Split out from Connect so the tuning
// can be asserted in tests without a live database.
func poolConfig(databaseURL string, maxConns int) (*pgxpool.Config, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}

	config.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeExec
	config.ConnConfig.StatementCacheCapacity = 0
	config.ConnConfig.DescriptionCacheCapacity = 0

	if maxConns <= 0 {
		maxConns = 5
	}
	config.MaxConns = int32(maxConns)
	config.MinConns = 0
	config.MaxConnIdleTime = 30 * time.Second
	config.MaxConnLifetime = 30 * time.Minute
	config.HealthCheckPeriod = time.Minute

	return config, nil
}

// ConnectSimple opens a single plain connection in simple-query-protocol mode.
// The migrate Job uses it: simple protocol is PgBouncer-safe over the transaction
// pooler AND supports the multi-statement DDL in the migration files. The caller
// owns the connection and must Close it.
func ConnectSimple(ctx context.Context, databaseURL string) (*pgx.Conn, error) {
	config, err := simpleConnConfig(databaseURL)
	if err != nil {
		return nil, err
	}

	conn, err := pgx.ConnectConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("connect postgres: %w", err)
	}

	if err := conn.Ping(ctx); err != nil {
		_ = conn.Close(ctx)
		return nil, fmt.Errorf("ping postgres: %w", err)
	}

	return conn, nil
}

// simpleConnConfig builds the migrate Job's connection config. Split out from
// ConnectSimple so the protocol mode can be asserted in tests without a database.
func simpleConnConfig(databaseURL string) (*pgx.ConnConfig, error) {
	config, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}
	config.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	return config, nil
}
