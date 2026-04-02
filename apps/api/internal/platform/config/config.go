package config

import (
	"os"
	"strings"
)

type Config struct {
	AppEnv          string
	HTTPAddr        string
	DatabaseURL     string
	RunDBMigrations bool
	ChromiumPath    string
}

func Load() (Config, error) {
	cfg := Config{
		AppEnv:          getEnv("APP_ENV", "development"),
		HTTPAddr:        getEnv("HTTP_ADDR", ":8080"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		RunDBMigrations: getEnvBool("RUN_DB_MIGRATIONS", false),
		ChromiumPath:    getEnv("CHROMIUM_PATH", ""),
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
