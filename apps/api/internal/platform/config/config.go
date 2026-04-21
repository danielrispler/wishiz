package config

import (
	"os"
	"strings"
	"time"
)

type Config struct {
	AppEnv                              string
	HTTPAddr                            string
	DatabaseURL                         string
	RunDBMigrations                     bool
	ChromiumPath                        string
	ExchangeRatesURL                    string
	ExchangeRateRefreshInterval         time.Duration
	ShareBaseURL                        string
	AndroidAppLinkSHA256CertFingerprint string
}

func Load() (Config, error) {
	cfg := Config{
		AppEnv:          getEnv("APP_ENV", "development"),
		HTTPAddr:        getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		RunDBMigrations: getEnvBool("RUN_DB_MIGRATIONS", false),
		ChromiumPath:    getEnv("CHROMIUM_PATH", ""),
		ExchangeRatesURL: getEnv(
			"EXCHANGE_RATES_URL",
			"https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml",
		),
		ExchangeRateRefreshInterval: getEnvDuration("EXCHANGE_RATE_REFRESH_INTERVAL", 12*time.Hour),
		ShareBaseURL:                getEnv("SHARE_BASE_URL", "https://wishiz.app"),
		AndroidAppLinkSHA256CertFingerprint: getEnv(
			"ANDROID_APP_LINK_SHA256_CERT_FINGERPRINT",
			"BC:00:5B:70:76:8D:1A:81:0A:82:21:CE:A1:DA:86:6B:F9:1B:0C:2E:52:A4:BD:38:4F:3D:C2:87:AB:F5:1D:3E",
		),
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
