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

// Worker periodically sweeps expired sessions and invites on a ticker. It mirrors
// the other background workers (product import, sitemap) and stops on ctx cancel.
type Worker struct {
	logger   *slog.Logger
	sessions SessionSweeper
	invites  InviteSweeper
	interval time.Duration
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

// Start runs an immediate sweep, then sweeps every interval until ctx is done.
func (w *Worker) Start(ctx context.Context) {
	go func() {
		ticker := time.NewTicker(w.interval)
		defer ticker.Stop()

		w.sweep(ctx)
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				w.sweep(ctx)
			}
		}
	}()
}

func (w *Worker) sweep(ctx context.Context) {
	if sessions, err := w.sessions.DeleteExpiredSessions(ctx); err != nil {
		w.logSweepError(ctx, "sweep expired sessions failed", err)
	} else if sessions > 0 {
		w.logger.Info("swept expired sessions", "deleted", sessions)
	}

	if invites, err := w.invites.DeleteExpiredInvites(ctx); err != nil {
		w.logSweepError(ctx, "sweep expired invites failed", err)
	} else if invites > 0 {
		w.logger.Info("swept expired invites", "deleted", invites)
	}
}

// logSweepError logs a sweep failure, downgrading to Debug when it is just the
// context being canceled (graceful shutdown is expected, not a real failure).
func (w *Worker) logSweepError(ctx context.Context, msg string, err error) {
	if errors.Is(err, context.Canceled) || ctx.Err() != nil {
		w.logger.Debug(msg+" (shutting down)", "error", err)
		return
	}
	w.logger.Error(msg, "error", err)
}
