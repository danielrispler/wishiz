package scrapehttp

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

type Service interface {
	Scrape(ctx context.Context, rawURL string, targetCurrencyCode string) (scrapeapp.Product, error)
}

type handler struct {
	logger  *slog.Logger
	service Service
	timeout time.Duration
}

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, service Service) {
	h := handler{
		logger:  logger,
		service: service,
		timeout: 35 * time.Second,
	}

	mux.HandleFunc("GET /scrape", h.scrapeProduct)
}

func (h handler) scrapeProduct(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), h.timeout)
	defer cancel()

	product, err := h.service.Scrape(
		ctx,
		r.URL.Query().Get("url"),
		r.URL.Query().Get("targetCurrencyCode"),
	)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, product)
}

func (h handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, context.DeadlineExceeded) {
		httpx.WriteError(w, http.StatusGatewayTimeout, "scrape_timeout", "scrape timed out", "")
		return
	}

	appErr, ok := scrapeapp.AsError(err)
	if !ok {
		h.logger.Error("scrape request failed", "method", r.Method, "path", r.URL.Path, "error", err)
		httpx.WriteError(w, http.StatusBadGateway, "scrape_failed", "could not extract complete product details", "")
		return
	}

	switch appErr.Code {
	case scrapeapp.ErrorCodeBadRequest:
		httpx.WriteError(w, http.StatusBadRequest, string(appErr.Code), appErr.Message, "url")
	case scrapeapp.ErrorCodeTimeout:
		httpx.WriteError(w, http.StatusGatewayTimeout, string(appErr.Code), appErr.Message, "")
	default:
		httpx.WriteError(w, http.StatusBadGateway, string(appErr.Code), appErr.Message, "")
	}
}
