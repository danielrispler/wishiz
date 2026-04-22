package application

import (
	"context"
	"log/slog"
	"sync"
	"time"
)

type Worker struct {
	logger       *slog.Logger
	service      *Service
	workerCount  int
	pollInterval time.Duration
}

func NewWorker(logger *slog.Logger, service *Service, workerCount int, pollInterval time.Duration) *Worker {
	if workerCount <= 0 {
		workerCount = 5
	}
	if pollInterval <= 0 {
		pollInterval = 2 * time.Second
	}
	if logger == nil {
		logger = slog.Default()
	}
	return &Worker{
		logger:       logger,
		service:      service,
		workerCount:  workerCount,
		pollInterval: pollInterval,
	}
}

func (w *Worker) Start(ctx context.Context) {
	var wg sync.WaitGroup
	for index := 0; index < w.workerCount; index++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			w.run(ctx, workerID)
		}(index + 1)
	}
	go func() {
		<-ctx.Done()
		wg.Wait()
	}()
}

func (w *Worker) run(ctx context.Context, workerID int) {
	ticker := time.NewTicker(w.pollInterval)
	defer ticker.Stop()

	for {
		processed, err := w.service.ProcessNext(ctx)
		if err != nil {
			w.logger.Error("product import worker tick failed", "worker_id", workerID, "error", err)
		}
		if processed {
			continue
		}

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
