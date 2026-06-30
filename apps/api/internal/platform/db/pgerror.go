package db

import (
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
)

// PostgreSQL SQLSTATE codes the repositories branch on.
const (
	sqlStateUniqueViolation     = "23505"
	sqlStateForeignKeyViolation = "23503"
)

// IsUniqueViolation reports whether err is a Postgres unique_violation (23505) —
// e.g. an INSERT colliding with a UNIQUE constraint. Use it to map a duplicate to
// a domain "already exists" rather than a generic 500.
func IsUniqueViolation(err error) bool {
	return hasSQLState(err, sqlStateUniqueViolation)
}

// IsForeignKeyViolation reports whether err is a Postgres foreign_key_violation
// (23503) — e.g. referencing a row that does not exist. Use it to map a bad
// reference to a domain validation error rather than a generic 500.
func IsForeignKeyViolation(err error) bool {
	return hasSQLState(err, sqlStateForeignKeyViolation)
}

func hasSQLState(err error, code string) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == code
}
