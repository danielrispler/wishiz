package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	applinkshttp "github.com/danielrispler/wishiz/apps/api/internal/features/applinks/adapters/http"
	authhttp "github.com/danielrispler/wishiz/apps/api/internal/features/auth/adapters/http"
	authpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/auth/adapters/postgres"
	authapp "github.com/danielrispler/wishiz/apps/api/internal/features/auth/application"
	healthhttp "github.com/danielrispler/wishiz/apps/api/internal/features/health/adapters/http"
	scrapefastpath "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/fastpath"
	scrapeheadless "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/headless"
	scrapehttp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/http"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	wishlisthttp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/http"
	wishlistpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/postgres"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
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

	mux := http.NewServeMux()
	applinkshttp.RegisterRoutes(mux, applinkshttp.Options{
		ShareBaseURL:                 cfg.ShareBaseURL,
		AndroidPackageName:           "com.example.wishiz",
		AndroidSHA256CertFingerprint: cfg.AndroidAppLinkSHA256CertFingerprint,
		IOSAppID:                     "P46VR4C98R.com.wishiz.beta",
	})
	healthhttp.RegisterRoutes(mux)

	resolver := net.DefaultResolver
	fastScraper := scrapefastpath.NewScraper(resolver)
	headlessScraper := scrapeheadless.NewScraper(cfg.ChromiumPath)
	defer headlessScraper.Close()

	scrapeService := scrapeapp.NewService(appLogger, fastScraper, headlessScraper, resolver)
	scrapehttp.RegisterRoutes(mux, appLogger, scrapeService)

	if cfg.DatabaseURL != "" {
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

		authRepo := authpostgres.NewRepository(pool)
		authService := authapp.NewService(authRepo)
		authhttp.RegisterRoutes(mux, appLogger, authService)

		wishlistRepo := wishlistpostgres.NewRepository(pool)
		wishlistService := wishlistapp.NewService(wishlistRepo)
		wishlisthttp.RegisterRoutes(mux, appLogger, wishlistService, authhttp.RequireAuth(authService))
	} else {
		appLogger.Info("starting api without database-backed wishlist routes")
	}

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
