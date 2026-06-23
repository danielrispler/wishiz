// Package maintenance runs periodic background housekeeping that keeps the
// database tidy. Today that is sweeping expired session tokens and unaccepted,
// expired share invites — rows that nothing else deletes once they lapse.
package maintenance

import (
	"context"
	"errors"
	"log/slog"
	"time"
)

// SessionSweeper deletes expired session rows, returning the count removed.
type SessionSweeper interface {
	DeleteExpiredSessions(ctx context.Context) (int64, error)
}

// InviteSweeper deletes expired, unaccepted invite rows, returning the count removed.
type InviteSweeper interface {
	DeleteExpiredInvites(ctx context.Context) (int64, error)
}

// DiscoverSweeper removes stale (TTL-expired) and overflow discover products,
// returning how many were expired and evicted by the global cap.
type DiscoverSweeper interface {
	SweepDiscoverProducts(ctx context.Context, maxRows int) (expired, evicted int64, err error)
}

// Worker periodically sweeps expired sessions and invites on a ticker. It mirrors
// the other background workers (product import, sitemap) and stops on ctx cancel.
type Worker struct {
	logger          *slog.Logger
	sessions        SessionSweeper
	invites         InviteSweeper
	discover        DiscoverSweeper
	discoverMaxRows int
	interval        time.Duration
}

// NewWorker builds a maintenance worker. A non-positive interval falls back to 1h.
func NewWorker(logger *slog.Logger, sessions SessionSweeper, invites InviteSweeper, interval time.Duration) *Worker {
	if interval <= 0 {
		interval = time.Hour
	}
	if logger == nil {
		logger = slog.Default()
	}
	return &Worker{
		logger:   logger,
		sessions: sessions,
		invites:  invites,
		interval: interval,
	}
}

// WithDiscoverSweeper wires the discover-product sweep (TTL + global cap) into
// the worker. It is only available when the DB is up, so it is set separately
// from the required session/invite sweepers. A non-positive maxRows disables the
// cap, leaving only the TTL sweep. Returns the worker for chaining.
func (w *Worker) WithDiscoverSweeper(sweeper DiscoverSweeper, maxRows int) *Worker {
	w.discover = sweeper
	w.discoverMaxRows = maxRows
	return w
}

// Sweep runs one housekeeping pass synchronously and returns the first sweep
// error (if any) so the api role's POST /internal/maintenance endpoint (driven by
// Cloud Scheduler) can report failure instead of always 200. A canceled context
// (graceful shutdown) is not treated as a failure. The in-process ticker is only
// started in the all role.
func (w *Worker) Sweep(ctx context.Context) error {
	return w.sweep(ctx)
}

// Start runs an immediate sweep, then sweeps every interval until ctx is done.
func (w *Worker) Start(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(w.interval)
		defer ticker.Stop()

		_ = w.sweep(ctx)
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				_ = w.sweep(ctx)
			}
		}
	}()
}

// sweep runs each housekeeping step, logging failures, and returns the joined
// non-shutdown errors so callers can surface a real failure. Context-cancel
// (shutdown) is downgraded to Debug and excluded from the returned error.
func (w *Worker) sweep(ctx context.Context) error {
	var errs []error

	if sessions, err := w.sessions.DeleteExpiredSessions(ctx); err != nil {
		errs = append(errs, w.logSweepError(ctx, "sweep expired sessions failed", err))
	} else if sessions > 0 {
		w.logger.Info("swept expired sessions", "deleted", sessions)
	}

	if invites, err := w.invites.DeleteExpiredInvites(ctx); err != nil {
		errs = append(errs, w.logSweepError(ctx, "sweep expired invites failed", err))
	} else if invites > 0 {
		w.logger.Info("swept expired invites", "deleted", invites)
	}

	if w.discover != nil {
		if expired, evicted, err := w.discover.SweepDiscoverProducts(ctx, w.discoverMaxRows); err != nil {
			errs = append(errs, w.logSweepError(ctx, "sweep discover products failed", err))
		} else if expired > 0 || evicted > 0 {
			w.logger.Info("swept discover products", "expired", expired, "over_cap_evicted", evicted)
		}
	}

	return errors.Join(errs...)
}

// logSweepError logs a sweep failure, downgrading to Debug when it is just the
// context being canceled (graceful shutdown is expected, not a real failure). It
// returns nil for the shutdown case and the error otherwise, so the caller only
// aggregates genuine failures.
func (w *Worker) logSweepError(ctx context.Context, msg string, err error) error {
	if errors.Is(err, context.Canceled) || ctx.Err() != nil {
		w.logger.Debug(msg+" (shutting down)", "error", err)
		return nil //nolint:nilerr // graceful shutdown is expected, not a sweep failure
	}
	w.logger.Error(msg, "error", err)
	return err
}
