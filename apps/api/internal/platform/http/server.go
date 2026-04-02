package httpx

import (
	"context"
	"log/slog"
	"net/http"
	"time"
)

func NewServer(addr string, handler http.Handler) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      40 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
}

func Shutdown(ctx context.Context, server *http.Server, logger *slog.Logger) error {
	logger.Info("shutting down api server")
	return server.Shutdown(ctx)
}
