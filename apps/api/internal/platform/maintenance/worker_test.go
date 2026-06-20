package maintenance

import (
	"context"
	"log/slog"
	"testing"
	"time"
)

// levelRecorder captures the level of the highest-severity record emitted.
type levelRecorder struct {
	max     slog.Level
	hasAny  bool
	lastMsg string
}

func (r *levelRecorder) Enabled(context.Context, slog.Level) bool { return true }
func (r *levelRecorder) Handle(_ context.Context, record slog.Record) error {
	if !r.hasAny || record.Level > r.max {
		r.max = record.Level
	}
	r.hasAny = true
	r.lastMsg = record.Message
	return nil
}
func (r *levelRecorder) WithAttrs([]slog.Attr) slog.Handler { return r }
func (r *levelRecorder) WithGroup(string) slog.Handler      { return r }

type canceledSweeper struct{}

func (canceledSweeper) DeleteExpiredSessions(context.Context) (int64, error) {
	return 0, context.Canceled
}
func (canceledSweeper) DeleteExpiredInvites(context.Context) (int64, error) {
	return 0, context.Canceled
}

type errSweeper struct{ err error }

func (e errSweeper) DeleteExpiredSessions(context.Context) (int64, error) { return 0, e.err }
func (e errSweeper) DeleteExpiredInvites(context.Context) (int64, error)  { return 0, e.err }

func TestSweepCanceledContextLogsBelowError(t *testing.T) {
	t.Parallel()

	rec := &levelRecorder{}
	worker := NewWorker(slog.New(rec), canceledSweeper{}, canceledSweeper{}, time.Hour)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	worker.sweep(ctx)

	if rec.max >= slog.LevelError {
		t.Fatalf("graceful-shutdown cancellation must not log at Error, got level %v", rec.max)
	}
}

func TestSweepRealErrorLogsError(t *testing.T) {
	t.Parallel()

	rec := &levelRecorder{}
	boom := context.DeadlineExceeded // a non-Canceled error stands in for a real failure
	worker := NewWorker(slog.New(rec), errSweeper{err: boom}, errSweeper{err: boom}, time.Hour)

	worker.sweep(context.Background())

	if rec.max != slog.LevelError {
		t.Fatalf("a real sweep failure must log at Error, got level %v", rec.max)
	}
}
