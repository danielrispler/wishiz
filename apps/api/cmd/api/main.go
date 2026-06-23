package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

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
	scrapeheadless "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/headless"
	scrapehttp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/http"
	scrapehttpfetch "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/httpfetch"
	scrapeshopify "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/shopify"
	scrapezenrows "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/zenrows"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	uploadshttp "github.com/danielrispler/wishiz/apps/api/internal/features/uploads/adapters/http"
	wishlisthttp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/http"
	wishlistpostgres "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/adapters/postgres"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/config"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/db"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/importdispatch"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/logger"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/maintenance"
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
	appLogger.Info("starting", "role", cfg.ServiceRole, "env", cfg.AppEnv)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	role := cfg.ServiceRole

	// migrate Job: own simple-protocol connection, apply migrations, exit.
	if role == config.RoleMigrate {
		return runMigrate(ctx, cfg, appLogger)
	}

	// Every other role uses the tuned pool when a database is configured.
	var pool *pgxpool.Pool
	if cfg.DatabaseURL != "" {
		p, connErr := db.Connect(ctx, cfg.DatabaseURL, cfg.DBMaxConns)
		if connErr != nil {
			return fmt.Errorf("connect postgres: %w", connErr)
		}
		defer p.Close()
		pool = p

		// Boot-migrate only in the single-instance all role; deployed roles rely on
		// the migrate Job so concurrent instances never race on migrations.
		if role == config.RoleAll && cfg.RunDBMigrations {
			appLogger.Info("running database migrations (dev-only)")
			if migErr := db.RunMigrations(ctx, pool); migErr != nil {
				return fmt.Errorf("run database migrations: %w", migErr)
			}
		}
	}

	// Scrape engine for roles that scrape. The paid ZenRows backstop is wired
	// whenever a key is present; it only fires on ScrapeImport (live import + the
	// weekly drain), never on the Scrape path used by /scrape and the discover crawl.
	var scrape *scrapeBundle
	if roleNeedsScrape(role) {
		scrape = setupScrape(cfg, appLogger, true)
		defer scrape.close()
	}

	// The weekly-batch Job needs the pool + scrape engine: run its task, then exit.
	if role == config.RoleWeeklyBatch {
		return runWeeklyBatch(ctx, cfg, appLogger, pool, scrape)
	}

	// Service roles (api, scraper, all): build the HTTP server.
	mux := http.NewServeMux()
	registerBaseRoutes(mux, cfg)

	if roleServesScrape(role) {
		scrapehttp.RegisterRoutes(mux, appLogger, scrape.service)
	}

	if pool != nil {
		cleanup, err := registerDBRoutes(ctx, cfg, appLogger, role, mux, pool, scrape)
		if err != nil {
			return err
		}
		defer cleanup()
	} else {
		appLogger.Info("starting api without database-backed routes")
	}

	return serve(ctx, cfg, appLogger, mux)
}

// registerDBRoutes wires the database-backed features and, in the all role,
// starts the in-process background loops. It is shared by api/scraper/all; which
// routes mount is gated by the role. It returns a cleanup that closes any
// long-lived clients it opened (Cloud Tasks dispatcher, GCS uploader) and an
// error when a required dependency is misconfigured, so boot fails fast rather
// than silently disabling a feature.
func registerDBRoutes(
	ctx context.Context,
	cfg config.Config,
	appLogger *slog.Logger,
	role string,
	mux *http.ServeMux,
	pool *pgxpool.Pool,
	scrape *scrapeBundle,
) (func(), error) {
	var closers []func()
	cleanup := func() {
		for i := len(closers) - 1; i >= 0; i-- {
			closers[i]()
		}
	}
	authRepo := authpostgres.NewRepository(pool)
	authService := authapp.NewService(authRepo)
	authMiddleware := func(next http.HandlerFunc) http.HandlerFunc {
		return authhttp.RequireAuth(authService, next)
	}

	wishlistRepo := wishlistpostgres.NewRepository(pool)
	wishlistService := wishlistapp.NewService(wishlistRepo)

	// The scrape service is only present on scrape-capable roles. api builds its
	// import/discover services with a nil scraper — the code paths that would
	// deref it (processing, discover seed) are never registered on api.
	var scrapeService *scrapeapp.Service
	if scrape != nil {
		scrapeService = scrape.service
	}

	productImportRepo := productimportpostgres.NewRepository(pool)
	productImportService := productimportapp.NewService(
		appLogger, productImportRepo, wishlistService, scrapeImporter(scrapeService), net.DefaultResolver,
	)

	discoverRepo := discoverpostgres.NewRepository(pool, cfg.DiscoverItemTTL)
	discoverService := discoverapp.NewService(discoverRepo, scrapeService)

	maintenanceWorker := maintenance.NewWorker(appLogger, authRepo, wishlistRepo, cfg.CleanupInterval).
		WithDiscoverSweeper(discoverRepo, cfg.DiscoverMaxProducts)

	if roleServesAPI(role) {
		authhttp.RegisterRoutes(mux, appLogger, authService)

		if cfg.UploadsEnabled {
			// Misconfigured uploads has no safe fallback (routes would 404), so fail
			// boot instead of starting healthy with uploads silently off.
			uploader, err := storage.NewGCSUploader(ctx, cfg.GCSBucket, cfg.GCSPublicBaseURL)
			if err != nil {
				cleanup()
				return nil, fmt.Errorf("configure image storage: %w", err)
			}
			closers = append(closers, func() { _ = uploader.Close() })
			uploadshttp.RegisterRoutes(mux, appLogger, uploader, authMiddleware)
		}

		// Cloud Tasks dispatch (live import). Absent locally/all -> in-process poller
		// drains. When enabled it requires an invoker SA, else it would enqueue
		// unauthenticated tasks the scraper IAM rejects — fail boot rather than
		// silently degrade to the drain Job.
		if cfg.LiveImportDispatchEnabled() {
			if cfg.ScraperInvokerSA == "" {
				cleanup()
				return nil, fmt.Errorf("live import dispatch requires SCRAPER_INVOKER_SA")
			}
			dispatcher, err := importdispatch.New(ctx, importdispatch.Config{
				QueuePath:      cfg.ImportTasksQueue,
				ScraperBaseURL: cfg.ScraperURL,
				Audience:       cfg.ScraperAudience,
				InvokerSA:      cfg.ScraperInvokerSA,
			})
			if err != nil {
				cleanup()
				return nil, fmt.Errorf("configure import dispatcher: %w", err)
			}
			closers = append(closers, func() { _ = dispatcher.Close() })
			productImportService = productImportService.WithDispatcher(dispatcher)
		}

		productimporthttp.RegisterRoutes(mux, appLogger, productImportService, authMiddleware)
		wishlisthttp.RegisterRoutes(mux, appLogger, wishlistService, authMiddleware)
		discoverhttp.RegisterRoutes(mux, appLogger, discoverService, authService, authMiddleware, cfg.InternalAPIKey)
	}

	if roleServesScrape(role) {
		productimporthttp.RegisterInternalRoutes(mux, appLogger, productImportService)
		discoverhttp.RegisterSeedRoutes(mux, appLogger, discoverService, cfg.InternalAPIKey)
	}

	if role == config.RoleAll {
		productimportapp.NewWorker(
			appLogger, productImportService, cfg.ProductImportWorkerCount, cfg.ProductImportPollInterval,
		).Start(ctx)
		discoverapp.NewSitemapWorker(
			appLogger, discoverRepo, scrapeService, cfg.DiscoverSitemapRefreshInterval,
		).Start(ctx)
		maintenanceWorker.Start(ctx)
	}

	return cleanup, nil
}

func registerBaseRoutes(mux *http.ServeMux, cfg config.Config) {
	applinkshttp.RegisterRoutes(mux, applinkshttp.Options{
		ShareBaseURL:                 cfg.ShareBaseURL,
		AndroidPackageName:           "com.example.wishiz",
		AndroidSHA256CertFingerprint: cfg.AndroidAppLinkSHA256CertFingerprint,
		IOSAppID:                     "P46VR4C98R.com.wishiz.beta",
	})
	healthhttp.RegisterRoutes(mux)
}

func serve(ctx context.Context, cfg config.Config, appLogger *slog.Logger, mux *http.ServeMux) error {
	server := httpx.NewServer(cfg.HTTPAddr, mux)
	serverErr := make(chan error, 1)
	go func() {
		appLogger.Info("starting api server", "addr", cfg.HTTPAddr, "role", cfg.ServiceRole)
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

// ---- Job roles ----

func runMigrate(ctx context.Context, cfg config.Config, appLogger *slog.Logger) error {
	if cfg.DatabaseURL == "" {
		return errors.New("migrate role requires DATABASE_URL")
	}
	conn, err := db.ConnectSimple(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect postgres (migrate): %w", err)
	}
	defer func() { _ = conn.Close(ctx) }()

	if err := db.RunMigrations(ctx, conn); err != nil {
		return fmt.Errorf("run database migrations: %w", err)
	}
	appLogger.Info("migrations applied")
	return nil
}

// runWeeklyBatch is the single weekly Cloud Run Job. It runs three independent
// steps in sequence — maintenance sweep, discover sitemap crawl, then drain
// pending imports — and exits non-zero if any step that reports errors failed, so
// a failed weekly run is visible in Cloud Run. Steps do not gate each other: a
// maintenance failure must not skip the crawl or the drain.
func runWeeklyBatch(
	ctx context.Context, cfg config.Config, appLogger *slog.Logger, pool *pgxpool.Pool, scrape *scrapeBundle,
) error {
	if pool == nil {
		return errors.New("weekly-batch role requires DATABASE_URL")
	}
	authRepo := authpostgres.NewRepository(pool)
	wishlistRepo := wishlistpostgres.NewRepository(pool)
	discoverRepo := discoverpostgres.NewRepository(pool, cfg.DiscoverItemTTL)

	// 1. Maintenance sweep (DB-only): expired sessions/invites + discover TTL/cap.
	errMaintenance := maintenance.NewWorker(appLogger, authRepo, wishlistRepo, cfg.CleanupInterval).
		WithDiscoverSweeper(discoverRepo, cfg.DiscoverMaxProducts).
		Sweep(ctx)

	// 2. Discover sitemap crawl (Chromium, Scrape only — never the paid backstop).
	discoverapp.NewSitemapWorker(
		appLogger, discoverRepo, scrape.service, cfg.DiscoverSitemapRefreshInterval,
	).Refresh(ctx)

	// 3. Drain pending imports: the only prod backstop now that import-drain is gone
	// — recovers jobs whose Cloud Task was never created or exhausted its retries.
	wishlistService := wishlistapp.NewService(wishlistRepo)
	importService := productimportapp.NewService(
		appLogger, productimportpostgres.NewRepository(pool), wishlistService, scrape.service, net.DefaultResolver,
	)
	processed, errDrain := importService.DrainPending(ctx, cfg.ImportDrainLimit)
	if errDrain == nil {
		appLogger.Info("weekly batch import drain finished", "processed", processed)
	}

	return errors.Join(errMaintenance, errDrain)
}

// ---- Scrape engine bundle ----

type scrapeBundle struct {
	service *scrapeapp.Service
	close   func()
}

// setupScrape builds the scrape engine, headless allocator and exchange-rate
// converter. The exchange cache is filled by one async refresh on cold start;
// the periodic refresh ticker is started only in the all role. withBackstop
// controls whether the paid ZenRows backstop is wired (import paths only).
func setupScrape(cfg config.Config, appLogger *slog.Logger, withBackstop bool) *scrapeBundle {
	resolver := net.DefaultResolver
	staticFetcher := scrapehttpfetch.New(resolver)
	headlessScraper := scrapeheadless.NewScraper(cfg.ChromiumPath, resolver, cfg.ScrapeRenderTimeout)

	var shopifyProbe scrapeapp.CandidateSource
	if cfg.ScrapeShopifyProbe {
		shopifyProbe = scrapeshopify.NewProbe(resolver)
	}

	var scrapeBackstop scrapeapp.Backstop
	if withBackstop && cfg.ZenRowsAPIKey != "" {
		scrapeBackstop = scrapezenrows.New(cfg.ZenRowsAPIKey, appLogger)
	}

	scrapeEngine := scrapeapp.NewEngine(scrapeapp.EngineConfig{
		InferDotComUSD: cfg.ScrapeInferDotComUSD,
		MaxPrice:       cfg.ScrapeMaxPrice,
	})

	exchangeConverter := scrapeapp.NewCachedExchangeConverter(cfg.ExchangeRatesURL, cfg.ExchangeRateRefreshInterval)
	switch cfg.ServiceRole {
	case config.RoleWeeklyBatch:
		// The weekly-batch Job drains imports (DOES convert currency); warm the rate
		// cache synchronously so the drain doesn't race a cold cache and force
		// needs_review. The sitemap crawl uses Scrape and needs no rates. A failed
		// fetch still degrades gracefully (review, not panic).
		if err := exchangeConverter.Refresh(); err != nil {
			appLogger.Warn("initial exchange rate refresh failed", "error", err)
		}
	default:
		// Long-lived roles (all, scraper): fill the cache in the background so a slow
		// ECB feed never blocks cold start; prices imported before the first refresh
		// lands are simply not yet converted (a failed conversion forces review).
		go func() {
			if err := exchangeConverter.Refresh(); err != nil {
				appLogger.Warn("initial exchange rate refresh failed", "error", err)
			}
		}()
	}
	var exchangeStop chan struct{}
	if cfg.ServiceRole == config.RoleAll {
		exchangeStop = make(chan struct{})
		exchangeConverter.Start(exchangeStop)
	}

	scrapeService := scrapeapp.NewService(
		appLogger, scrapeEngine, staticFetcher, headlessScraper, shopifyProbe, resolver, exchangeConverter,
		scrapeapp.ServiceConfig{
			Budget:               cfg.ScrapeBudget,
			MaxConcurrentRenders: cfg.ScrapeMaxConcurrentRenders,
			Backstop:             scrapeBackstop,
			BackstopTimeout:      cfg.ZenRowsTimeout,
		},
	)

	return &scrapeBundle{
		service: scrapeService,
		close: func() {
			headlessScraper.Close()
			if exchangeStop != nil {
				close(exchangeStop)
			}
		},
	}
}

// scrapeImporter adapts the concrete scrape service to the productimports
// Scraper port, returning a typed-nil-safe value when there is no engine.
func scrapeImporter(s *scrapeapp.Service) productimportapp.Scraper {
	if s == nil {
		return nil
	}
	return s
}

// ---- Role predicates ----

func roleNeedsScrape(role string) bool {
	switch role {
	case config.RoleScraper, config.RoleWeeklyBatch, config.RoleAll:
		return true
	default:
		return false
	}
}

func roleServesAPI(role string) bool {
	return role == config.RoleAPI || role == config.RoleAll
}

func roleServesScrape(role string) bool {
	return role == config.RoleScraper || role == config.RoleAll
}
