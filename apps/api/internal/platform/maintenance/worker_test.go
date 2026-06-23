package maintenance

import (
	"context"
	"io"
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

type okSweeper struct{}

func (okSweeper) DeleteExpiredSessions(context.Context) (int64, error) { return 0, nil }
func (okSweeper) DeleteExpiredInvites(context.Context) (int64, error)  { return 0, nil }

type recordingDiscoverSweeper struct {
	calls   int
	maxRows int
}

func (s *recordingDiscoverSweeper) SweepDiscoverProducts(
	_ context.Context, maxRows int,
) (expired, evicted int64, err error) {
	s.calls++
	s.maxRows = maxRows
	return 1, 2, nil
}

func TestSweepInvokesDiscoverSweeperWithCap(t *testing.T) {
	t.Parallel()

	disc := &recordingDiscoverSweeper{}
	worker := NewWorker(slog.New(slog.NewTextHandler(io.Discard, nil)), okSweeper{}, okSweeper{}, time.Hour).
		WithDiscoverSweeper(disc, 2000)

	_ = worker.sweep(context.Background())

	if disc.calls != 1 {
		t.Fatalf("expected discover sweeper called once, got %d", disc.calls)
	}
	if disc.maxRows != 2000 {
		t.Fatalf("expected maxRows 2000 passed through, got %d", disc.maxRows)
	}
}

func TestSweepWithoutDiscoverSweeperIsNoOp(t *testing.T) {
	t.Parallel()

	// No WithDiscoverSweeper: discover field is nil and must not panic.
	worker := NewWorker(slog.New(slog.NewTextHandler(io.Discard, nil)), okSweeper{}, okSweeper{}, time.Hour)
	_ = worker.sweep(context.Background())
}

func TestSweepCanceledContextLogsBelowError(t *testing.T) {
	t.Parallel()

	rec := &levelRecorder{}
	worker := NewWorker(slog.New(rec), canceledSweeper{}, canceledSweeper{}, time.Hour)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_ = worker.sweep(ctx)

	if rec.max >= slog.LevelError {
		t.Fatalf("graceful-shutdown cancellation must not log at Error, got level %v", rec.max)
	}
}

func TestSweepRealErrorLogsError(t *testing.T) {
	t.Parallel()

	rec := &levelRecorder{}
	boom := context.DeadlineExceeded // a non-Canceled error stands in for a real failure
	worker := NewWorker(slog.New(rec), errSweeper{err: boom}, errSweeper{err: boom}, time.Hour)

	_ = worker.sweep(context.Background())

	if rec.max != slog.LevelError {
		t.Fatalf("a real sweep failure must log at Error, got level %v", rec.max)
	}
}

func TestSweepReturnsErrorOnRealFailure(t *testing.T) {
	t.Parallel()

	boom := context.DeadlineExceeded // a non-Canceled error stands in for a real failure
	worker := NewWorker(slog.New(slog.NewTextHandler(io.Discard, nil)), errSweeper{err: boom}, okSweeper{}, time.Hour)

	if err := worker.Sweep(context.Background()); err == nil {
		t.Fatal("Sweep must return a non-nil error when a step genuinely fails")
	}
}

func TestSweepReturnsNilOnShutdown(t *testing.T) {
	t.Parallel()

	worker := NewWorker(slog.New(slog.NewTextHandler(io.Discard, nil)), canceledSweeper{}, canceledSweeper{}, time.Hour)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if err := worker.Sweep(ctx); err != nil {
		t.Fatalf("a canceled (shutdown) sweep must not be reported as failure, got %v", err)
	}
}
