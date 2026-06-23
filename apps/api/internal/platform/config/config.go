package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

// Service roles select which slice of the binary runs. The same image is
// deployed several ways and SERVICE_ROLE branches the wiring in cmd/api/main.go.
//   - all            local docker-compose / tests: the monolith (every route +
//     all in-process background loops + boot-migrate).
//   - api            request-driven service: user/read routes, import enqueue
//     (+ Cloud Tasks dispatch), maintenance endpoint. No scrape engine, no loops.
//   - scraper        request-driven service: scrape engine + internal scrape
//     routes (live import process, discover seed). No loops.
//   - migrate        run-to-completion Job: apply migrations, then exit.
//   - discover-batch run-to-completion Job: one discover sitemap refresh, exit.
//   - import-drain   run-to-completion Job: drain pending imports, exit.
const (
	RoleAll           = "all"
	RoleAPI           = "api"
	RoleScraper       = "scraper"
	RoleMigrate       = "migrate"
	RoleDiscoverBatch = "discover-batch"
	RoleImportDrain   = "import-drain"
)

type Config struct {
	AppEnv                              string
	ServiceRole                         string
	HTTPAddr                            string
	DatabaseURL                         string
	DBMaxConns                          int
	RunDBMigrations                     bool
	UploadsEnabled                      bool
	GCSBucket                           string
	GCSPublicBaseURL                    string
	ChromiumPath                        string
	ScrapeBudget                        time.Duration
	ScrapeRenderTimeout                 time.Duration
	ScrapeMaxConcurrentRenders          int
	ScrapeShopifyProbe                  bool
	ScrapeInferDotComUSD                bool
	ScrapeMaxPrice                      float64
	ZenRowsAPIKey                       string
	ZenRowsTimeout                      time.Duration
	ExchangeRatesURL                    string
	ExchangeRateRefreshInterval         time.Duration
	ProductImportWorkerCount            int
	ProductImportPollInterval           time.Duration
	DiscoverSitemapRefreshInterval      time.Duration
	DiscoverItemTTL                     time.Duration
	DiscoverMaxProducts                 int
	CleanupInterval                     time.Duration
	ShareBaseURL                        string
	AndroidAppLinkSHA256CertFingerprint string
	InternalAPIKey                      string
	// Cloud Tasks live-import dispatch (api role). When ImportTasksQueue and
	// ScraperURL are both set, enqueuing an import creates a Cloud Task that
	// targets the scraper's process route with an OIDC token. Empty (all/local)
	// disables the dispatcher and the in-process poller drains imports instead.
	ImportTasksQueue string
	ScraperURL       string
	ScraperAudience  string
	ScraperInvokerSA string
	ImportDrainLimit int
}

// LiveImportDispatchEnabled reports whether Cloud Tasks live-import dispatch is
// configured (queue + scraper URL both set). When true the dispatcher must also
// have ScraperInvokerSA, else it would enqueue unauthenticated tasks the scraper
// rejects — callers enforce that as a fail-fast boot check.
func (c Config) LiveImportDispatchEnabled() bool {
	return c.ImportTasksQueue != "" && c.ScraperURL != ""
}

func Load() (Config, error) {
	cfg := Config{
		AppEnv:                     getEnv("APP_ENV", "development"),
		ServiceRole:                getEnv("SERVICE_ROLE", RoleAll),
		HTTPAddr:                   getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:                os.Getenv("DATABASE_URL"),
		DBMaxConns:                 getEnvInt("DB_MAX_CONNS", 5),
		RunDBMigrations:            getEnvBool("RUN_DB_MIGRATIONS", false),
		UploadsEnabled:             getEnvBool("UPLOADS_ENABLED", false),
		GCSBucket:                  getEnv("BUCKET_NAME", ""),
		GCSPublicBaseURL:           getEnv("GCS_PUBLIC_BASE_URL", "https://storage.googleapis.com"),
		ChromiumPath:               getEnv("CHROMIUM_PATH", ""),
		ScrapeBudget:               getEnvDuration("SCRAPE_BUDGET", 30*time.Second),
		ScrapeRenderTimeout:        getEnvDuration("SCRAPE_RENDER_TIMEOUT", 26*time.Second),
		ScrapeMaxConcurrentRenders: getEnvInt("SCRAPE_MAX_CONCURRENT_RENDERS", 3),
		ScrapeShopifyProbe:         getEnvBool("SCRAPE_SHOPIFY_PROBE", true),
		ScrapeInferDotComUSD:       getEnvBool("SCRAPE_INFER_DOTCOM_USD", false),
		ScrapeMaxPrice:             getEnvFloat("SCRAPE_MAX_PRICE", 1e7),
		ZenRowsAPIKey:              getEnv("ZENROWS_API_KEY", ""),
		ZenRowsTimeout:             getEnvDuration("ZENROWS_TIMEOUT", 30*time.Second),
		ExchangeRatesURL: getEnv(
			"EXCHANGE_RATES_URL",
			"https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml",
		),
		ExchangeRateRefreshInterval: getEnvDuration("EXCHANGE_RATE_REFRESH_INTERVAL", 12*time.Hour),
		ProductImportWorkerCount:    getEnvInt("PRODUCT_IMPORT_WORKER_COUNT", 5),
		ProductImportPollInterval:   getEnvDuration("PRODUCT_IMPORT_POLL_INTERVAL", 2*time.Second),
		DiscoverSitemapRefreshInterval: getEnvDuration(
			"DISCOVER_SITEMAP_REFRESH_INTERVAL",
			24*time.Hour,
		),
		DiscoverItemTTL:     getEnvDuration("DISCOVER_ITEM_TTL", 720*time.Hour),
		DiscoverMaxProducts: getEnvInt("DISCOVER_MAX_PRODUCTS", 2000),
		CleanupInterval:     getEnvDuration("CLEANUP_INTERVAL", time.Hour),
		ShareBaseURL:        getEnv("SHARE_BASE_URL", "https://wishiz.app"),
		AndroidAppLinkSHA256CertFingerprint: getEnv(
			"ANDROID_APP_LINK_SHA256_CERT_FINGERPRINT",
			"BC:00:5B:70:76:8D:1A:81:0A:82:21:CE:A1:DA:86:6B:F9:1B:0C:2E:52:A4:BD:38:4F:3D:C2:87:AB:F5:1D:3E",
		),
		InternalAPIKey:   os.Getenv("INTERNAL_API_KEY"),
		ImportTasksQueue: getEnv("IMPORT_TASKS_QUEUE", ""),
		ScraperURL:       getEnv("SCRAPER_URL", ""),
		ScraperInvokerSA: getEnv("SCRAPER_INVOKER_SA", ""),
		ImportDrainLimit: getEnvInt("IMPORT_DRAIN_LIMIT", 20),
	}

	// SCRAPER_AUDIENCE defaults to the scraper URL: an OIDC token's audience must
	// match the receiving Cloud Run service's URL unless explicitly overridden.
	cfg.ScraperAudience = getEnv("SCRAPER_AUDIENCE", cfg.ScraperURL)

	// Cloud Run injects PORT and crashes the instance if the server does not bind
	// it. PORT takes precedence over HTTP_ADDR so an injected port always wins.
	if port := strings.TrimSpace(os.Getenv("PORT")); port != "" {
		cfg.HTTPAddr = ":" + port
	}

	return cfg, nil
}

func getEnv(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	return value
}

func getEnvBool(key string, fallback bool) bool {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	switch strings.ToLower(value) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func getEnvInt(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func getEnvFloat(key string, fallback float64) float64 {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return fallback
	}
	return parsed
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	duration, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return duration
}
