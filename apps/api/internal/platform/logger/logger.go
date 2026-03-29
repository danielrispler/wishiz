package logger

import (
	"log/slog"
	"os"
)

func New(appEnv string) *slog.Logger {
	level := slog.LevelInfo
	if appEnv == "development" {
		level = slog.LevelDebug
	}

	return slog.New(
		slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
			Level: level,
		}),
	)
}
