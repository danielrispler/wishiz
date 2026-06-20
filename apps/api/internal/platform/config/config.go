package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	AppEnv                              string
	HTTPAddr                            string
	DatabaseURL                         string
	RunDBMigrations                     bool
	UploadsEnabled                      bool
	StorageS3Endpoint                   string
	StorageS3Region                     string
	StorageS3Bucket                     string
	StorageS3AccessKeyID                string
	StorageS3SecretAccessKey            string
	StorageS3UsePathStyle               bool
	StoragePublicBaseURL                string
	ChromiumPath                        string
	ScrapeBudget                        time.Duration
	ScrapeRenderTimeout                 time.Duration
	ScrapeMaxConcurrentRenders          int
	ScrapeShopifyProbe                  bool
	ScrapeInferDotComUSD                bool
	ScrapeMaxPrice                      float64
	ExchangeRatesURL                    string
	ExchangeRateRefreshInterval         time.Duration
	ProductImportWorkerCount            int
	ProductImportPollInterval           time.Duration
	DiscoverSitemapRefreshInterval      time.Duration
	CleanupInterval                     time.Duration
	ShareBaseURL                        string
	AndroidAppLinkSHA256CertFingerprint string
	InternalAPIKey                      string
}

func Load() (Config, error) {
	cfg := Config{
		AppEnv:                     getEnv("APP_ENV", "development"),
		HTTPAddr:                   getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:                os.Getenv("DATABASE_URL"),
		RunDBMigrations:            getEnvBool("RUN_DB_MIGRATIONS", false),
		UploadsEnabled:             getEnvBool("UPLOADS_ENABLED", false),
		StorageS3Endpoint:          getEnv("STORAGE_S3_ENDPOINT", ""),
		StorageS3Region:            getEnv("STORAGE_S3_REGION", "us-east-1"),
		StorageS3Bucket:            getEnv("STORAGE_S3_BUCKET", ""),
		StorageS3AccessKeyID:       getEnv("STORAGE_S3_ACCESS_KEY_ID", ""),
		StorageS3SecretAccessKey:   getEnv("STORAGE_S3_SECRET_ACCESS_KEY", ""),
		StorageS3UsePathStyle:      getEnvBool("STORAGE_S3_USE_PATH_STYLE", true),
		StoragePublicBaseURL:       getEnv("STORAGE_PUBLIC_BASE_URL", ""),
		ChromiumPath:               getEnv("CHROMIUM_PATH", ""),
		ScrapeBudget:               getEnvDuration("SCRAPE_BUDGET", 30*time.Second),
		ScrapeRenderTimeout:        getEnvDuration("SCRAPE_RENDER_TIMEOUT", 26*time.Second),
		ScrapeMaxConcurrentRenders: getEnvInt("SCRAPE_MAX_CONCURRENT_RENDERS", 3),
		ScrapeShopifyProbe:         getEnvBool("SCRAPE_SHOPIFY_PROBE", true),
		ScrapeInferDotComUSD:       getEnvBool("SCRAPE_INFER_DOTCOM_USD", false),
		ScrapeMaxPrice:             getEnvFloat("SCRAPE_MAX_PRICE", 1e7),
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
		CleanupInterval: getEnvDuration("CLEANUP_INTERVAL", time.Hour),
		ShareBaseURL:    getEnv("SHARE_BASE_URL", "https://wishiz.app"),
		AndroidAppLinkSHA256CertFingerprint: getEnv(
			"ANDROID_APP_LINK_SHA256_CERT_FINGERPRINT",
			"BC:00:5B:70:76:8D:1A:81:0A:82:21:CE:A1:DA:86:6B:F9:1B:0C:2E:52:A4:BD:38:4F:3D:C2:87:AB:F5:1D:3E",
		),
		InternalAPIKey: os.Getenv("INTERNAL_API_KEY"),
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
