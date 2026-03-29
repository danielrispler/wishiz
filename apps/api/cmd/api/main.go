package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	healthhttp "github.com/danielrispler/wishiz/apps/api/internal/features/health/adapters/http"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	wishlisthttp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/http"
	wishlistpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/postgres"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/config"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/db"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/logger"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("api startup failed: %v", err)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	appLogger := logger.New(cfg.AppEnv)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect postgres: %w", err)
	}
	defer pool.Close()

	if cfg.RunDBMigrations {
		appLogger.Info("running database migrations (dev-only)")
		if err := db.RunMigrations(ctx, pool); err != nil {
			return fmt.Errorf("run database migrations: %w", err)
		}
	}

	wishlistRepo := wishlistpostgres.NewRepository(pool)
	wishlistService := wishlistapp.NewService(wishlistRepo)
	mux := http.NewServeMux()
	healthhttp.RegisterRoutes(mux)
	wishlisthttp.RegisterRoutes(mux, appLogger, wishlistService)

	server := httpx.NewServer(cfg.HTTPAddr, mux)

	serverErr := make(chan error, 1)

	go func() {
		appLogger.Info("starting api server", "addr", cfg.HTTPAddr, "env", cfg.AppEnv)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	select {
	case err := <-serverErr:
		return fmt.Errorf("serve http: %w", err)
	case <-ctx.Done():
		appLogger.Info("shutdown signal received")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := httpx.Shutdown(shutdownCtx, server, appLogger); err != nil {
		return fmt.Errorf("shutdown http server: %w", err)
	}

	return nil
}
