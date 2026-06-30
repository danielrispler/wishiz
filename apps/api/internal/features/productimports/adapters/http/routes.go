package http

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

type Service interface {
	Create(ctx context.Context, input *application.CreateJobInput) (domain.Job, bool, error)
	List(ctx context.Context, input application.ListJobsInput) ([]domain.Job, error)
	Retry(ctx context.Context, id string) (domain.Job, error)
	Acknowledge(ctx context.Context, id string) (domain.Job, error)
	Assign(ctx context.Context, id string, wishlistID string) (domain.Job, error)
}

type AuthMiddleware func(http.HandlerFunc) http.HandlerFunc

type handler struct {
	logger  *slog.Logger
	service Service
}

type createJobRequest struct {
	WishlistID         string `json:"wishlistId"`
	SharedText         string `json:"sharedText"`
	ClientRequestID    string `json:"clientRequestId"`
	TargetCurrencyCode string `json:"targetCurrencyCode"`
}

type assignJobRequest struct {
	WishlistID string `json:"wishlistId"`
}

type jobResponse struct {
	ID                 string     `json:"id"`
	UserID             string     `json:"userId"`
	WishlistID         *string    `json:"wishlistId,omitempty"`
	ClientRequestID    string     `json:"clientRequestId"`
	NormalizedURL      string     `json:"normalizedUrl"`
	Domain             string     `json:"domain"`
	TargetCurrencyCode string     `json:"targetCurrencyCode"`
	Status             string     `json:"status"`
	AttemptCount       int        `json:"attemptCount"`
	LastAttemptedAt    *time.Time `json:"lastAttemptedAt"`
	LastError          *string    `json:"lastError"`
	ErrorCode          *string    `json:"errorCode"`
	Retryable          bool       `json:"retryable"`
	Title              *string    `json:"title"`
	PriceLabel         *string    `json:"priceLabel"`
	PriceAmount        *string    `json:"priceAmount"`
	PriceAmountMax     *string    `json:"priceAmountMax"`
	PriceCurrencyCode  *string    `json:"priceCurrencyCode"`
	PriceConfidence    *string    `json:"priceConfidence"`
	PriceSource        *string    `json:"priceSource"`
	PriceWarnings      []string   `json:"priceWarnings"`
	ImageURL           *string    `json:"imageUrl"`
	Completeness       int        `json:"completeness"`
	ProgressStage      string     `json:"progressStage"`
	ProgressPercent    int        `json:"progressPercent"`
	CreatedItemID      *string    `json:"createdItemId"`
	AcknowledgedAt     *time.Time `json:"acknowledgedAt"`
	CreatedAt          time.Time  `json:"createdAt"`
	UpdatedAt          time.Time  `json:"updatedAt"`
}

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, service Service, authMiddleware AuthMiddleware) {
	if authMiddleware == nil {
		authMiddleware = func(next http.HandlerFunc) http.HandlerFunc { return next }
	}
	h := handler{logger: logger, service: service}

	mux.HandleFunc("POST /product-imports", authMiddleware(withAuthenticatedUser(h.createJob)))
	mux.HandleFunc("GET /product-imports", authMiddleware(withAuthenticatedUser(h.listJobs)))
	mux.HandleFunc("POST /product-imports/{id}/retry", authMiddleware(withAuthenticatedUser(h.retryJob)))
	mux.HandleFunc("POST /product-imports/{id}/acknowledge", authMiddleware(withAuthenticatedUser(h.acknowledgeJob)))
	mux.HandleFunc("POST /product-imports/{id}/assign", authMiddleware(withAuthenticatedUser(h.assignJob)))
}

// Processor handles directed, out-of-band processing of a single import job.
// It backs the internal route the Cloud Tasks dispatcher targets on the scraper
// service.
type Processor interface {
	ProcessByID(ctx context.Context, jobID string) error
}

// RegisterInternalRoutes mounts the internal scrape-side route that processes a
// directed import (the Cloud Tasks target on the scraper service). Access is
// gated at the platform layer (Cloud Run IAM / OIDC), so there is no app-level
// auth here. A non-2xx response signals Cloud Tasks to retry.
func RegisterInternalRoutes(mux *http.ServeMux, logger *slog.Logger, processor Processor) {
	h := internalHandler{logger: logger, processor: processor}
	mux.HandleFunc("POST /internal/imports/{id}/process", h.processJob)
}

type internalHandler struct {
	logger    *slog.Logger
	processor Processor
}

func (h internalHandler) processJob(w http.ResponseWriter, r *http.Request) {
	jobID := r.PathValue("id")
	if jobID == "" {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", "job id is required", "")
		return
	}
	if err := h.processor.ProcessByID(r.Context(), jobID); err != nil {
		// The outcome did not persist; let Cloud Tasks retry.
		h.logger.Error("process import job failed", "job_id", jobID, "error", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func withAuthenticatedUser(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authctx.UserFromContext(r.Context()); !ok {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
			return
		}
		h(w, r)
	}
}

func (h handler) createJob(w http.ResponseWriter, r *http.Request) {
	var request createJobRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}
	started := time.Now()
	job, existing, err := h.service.Create(r.Context(), &application.CreateJobInput{
		WishlistID:         request.WishlistID,
		SharedText:         request.SharedText,
		ClientRequestID:    request.ClientRequestID,
		TargetCurrencyCode: request.TargetCurrencyCode,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	h.logger.Info("product import enqueued", "job_id", job.ID, "user_id", job.UserID, "domain", job.Domain, "existing", existing, "duration_ms", time.Since(started).Milliseconds())
	status := http.StatusCreated
	if existing {
		status = http.StatusOK
	}
	httpx.WriteJSON(w, status, mapJob(job))
}

func (h handler) listJobs(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	jobs, err := h.service.List(r.Context(), application.ListJobsInput{
		Status: r.URL.Query().Get("status"),
		Limit:  limit,
		Offset: offset,
	})
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	response := make([]jobResponse, 0, len(jobs))
	for _, job := range jobs {
		response = append(response, mapJob(job))
	}
	httpx.WriteJSON(w, http.StatusOK, response)
}

func (h handler) retryJob(w http.ResponseWriter, r *http.Request) {
	job, err := h.service.Retry(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, mapJob(job))
}

func (h handler) acknowledgeJob(w http.ResponseWriter, r *http.Request) {
	job, err := h.service.Acknowledge(r.Context(), r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, mapJob(job))
}

func (h handler) assignJob(w http.ResponseWriter, r *http.Request) {
	var request assignJobRequest
	if err := httpx.DecodeJSON(w, r, &request); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}
	job, err := h.service.Assign(r.Context(), r.PathValue("id"), request.WishlistID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, mapJob(job))
}

func (h handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	if appErr, ok := application.AsError(err); ok {
		switch appErr.Code {
		case application.ErrorCodeValidation:
			httpx.WriteError(w, http.StatusBadRequest, string(appErr.Code), appErr.Message, appErr.Field)
		case application.ErrorCodeNotFound:
			httpx.WriteError(w, http.StatusNotFound, string(appErr.Code), appErr.Message, appErr.Field)
		case application.ErrorCodeConflict:
			httpx.WriteError(w, http.StatusConflict, string(appErr.Code), appErr.Message, appErr.Field)
		default:
			httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		}
		return
	}
	if scrapeErr, ok := scrapeapp.AsError(err); ok {
		switch scrapeErr.Code {
		case scrapeapp.ErrorCodeBadRequest:
			httpx.WriteError(w, http.StatusBadRequest, string(scrapeErr.Code), scrapeErr.Message, "")
		default:
			httpx.WriteError(w, http.StatusBadGateway, string(scrapeErr.Code), scrapeErr.Message, "")
		}
		return
	}
	if wishlistErr, ok := wishlistapp.AsError(err); ok {
		switch wishlistErr.Code {
		case wishlistapp.ErrorCodeValidation:
			httpx.WriteError(w, http.StatusBadRequest, string(wishlistErr.Code), wishlistErr.Message, wishlistErr.Field)
		case wishlistapp.ErrorCodeWishlistNotFound:
			httpx.WriteError(w, http.StatusNotFound, string(wishlistErr.Code), wishlistErr.Message, wishlistErr.Field)
		default:
			httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		}
		return
	}

	h.logger.Error("product import request failed", "method", r.Method, "path", r.URL.Path, "error", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
}

func mapJob(job domain.Job) jobResponse {
	return jobResponse{
		ID:                 job.ID,
		UserID:             job.UserID,
		WishlistID:         job.WishlistID,
		ClientRequestID:    job.ClientRequestID,
		NormalizedURL:      job.NormalizedURL,
		Domain:             job.Domain,
		TargetCurrencyCode: job.TargetCurrencyCode,
		Status:             job.Status,
		AttemptCount:       job.AttemptCount,
		LastAttemptedAt:    job.LastAttemptedAt,
		LastError:          job.LastError,
		ErrorCode:          job.ErrorCode,
		Retryable:          job.Retryable,
		Title:              job.Title,
		PriceLabel:         job.PriceLabel,
		PriceAmount:        job.PriceAmount,
		PriceAmountMax:     job.PriceAmountMax,
		PriceCurrencyCode:  job.PriceCurrencyCode,
		PriceConfidence:    job.PriceConfidence,
		PriceSource:        job.PriceSource,
		PriceWarnings:      job.PriceWarnings,
		ImageURL:           job.ImageURL,
		Completeness:       job.Completeness,
		ProgressStage:      job.ProgressStage,
		ProgressPercent:    job.ProgressPercent,
		CreatedItemID:      job.CreatedItemID,
		AcknowledgedAt:     job.AcknowledgedAt,
		CreatedAt:          job.CreatedAt,
		UpdatedAt:          job.UpdatedAt,
	}
}
