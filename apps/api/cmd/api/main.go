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
	discoverhttp "github.com/danielrispler/wishiz/apps/api/internal/features/discover/adapters/http"
	discoverpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/discover/adapters/postgres"
	discoverapp "github.com/danielrispler/wishiz/apps/api/internal/features/discover/application"
	healthhttp "github.com/danielrispler/wishiz/apps/api/internal/features/health/adapters/http"
	productimporthttp "github.com/danielrispler/wishiz/apps/api/internal/features/productimports/adapters/http"
	productimportpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/productimports/adapters/postgres"
	productimportapp "github.com/danielrispler/wishiz/apps/api/internal/features/productimports/application"
	scrapefastpath "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/fastpath"
	scrapeheadless "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/headless"
	scrapehttp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/http"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	uploadshttp "github.com/danielrispler/wishiz/apps/api/internal/features/uploads/adapters/http"
	wishlisthttp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/http"
	wishlistpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/postgres"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/config"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/db"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/logger"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/storage"
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
	if cfg.AppEnv == "production" && cfg.DatabaseURL == "" {
		return errors.New("DATABASE_URL is required in production")
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
	headlessScraper := scrapeheadless.NewScraper(cfg.ChromiumPath, resolver)
	defer headlessScraper.Close()

	exchangeConverter := scrapeapp.NewCachedExchangeConverter(cfg.ExchangeRatesURL, cfg.ExchangeRateRefreshInterval)
	if err := exchangeConverter.Refresh(); err != nil {
		appLogger.Warn("initial exchange rate refresh failed", "error", err)
	}
	exchangeStop := make(chan struct{})
	defer close(exchangeStop)
	exchangeConverter.Start(exchangeStop)

	scrapeService := scrapeapp.NewService(appLogger, fastScraper, headlessScraper, resolver, exchangeConverter)
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

		if cfg.UploadsEnabled {
			imageUploader, err := storage.NewS3Uploader(storage.S3Config{
				Endpoint:        cfg.StorageS3Endpoint,
				Region:          cfg.StorageS3Region,
				Bucket:          cfg.StorageS3Bucket,
				AccessKeyID:     cfg.StorageS3AccessKeyID,
				SecretAccessKey: cfg.StorageS3SecretAccessKey,
				UsePathStyle:    cfg.StorageS3UsePathStyle,
				PublicBaseURL:   cfg.StoragePublicBaseURL,
			})
			if err != nil {
				return fmt.Errorf("configure image storage: %w", err)
			}
			uploadshttp.RegisterRoutes(
				mux,
				appLogger,
				imageUploader,
				func(next http.HandlerFunc) http.HandlerFunc {
					return authhttp.RequireAuth(authService, next)
				},
			)
		}

		wishlistRepo := wishlistpostgres.NewRepository(pool)
		wishlistService := wishlistapp.NewService(wishlistRepo)
		productImportRepo := productimportpostgres.NewRepository(pool)
		productImportService := productimportapp.NewService(appLogger, productImportRepo, wishlistService, scrapeService, resolver)
		productImportWorker := productimportapp.NewWorker(
			appLogger,
			productImportService,
			cfg.ProductImportWorkerCount,
			cfg.ProductImportPollInterval,
		)
		productImportWorker.Start(ctx)
		productimporthttp.RegisterRoutes(
			mux,
			appLogger,
			productImportService,
			func(next http.HandlerFunc) http.HandlerFunc {
				return authhttp.RequireAuth(authService, next)
			},
		)
		wishlisthttp.RegisterRoutes(
			mux,
			appLogger,
			wishlistService,
			func(next http.HandlerFunc) http.HandlerFunc {
				return authhttp.RequireAuth(authService, next)
			},
		)

		discoverRepo := discoverpostgres.NewRepository(pool)
		discoverService := discoverapp.NewService(discoverRepo, scrapeService)
		discoverhttp.RegisterRoutes(
			mux,
			appLogger,
			discoverService,
			authService,
			func(next http.HandlerFunc) http.HandlerFunc {
				return authhttp.RequireAuth(authService, next)
			},
			cfg.InternalAPIKey,
		)
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
