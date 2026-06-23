package application

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"regexp"
	"strings"
	"sync"
	"time"

	importdomain "github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/ports"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	wishlistdomain "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
)

const (
	ErrorCodeTimeout         = "timeout"
	ErrorCodeTransientScrape = "transient_scrape_error"
	ErrorCodeIncomplete      = "incomplete_product"
	ErrorCodeItemCreate      = "item_create_failed"
	// ErrorCodeUnsupported = the store hard-blocks automated import (anti-bot).
	// Terminal and NON-retryable: the UI tells the user to add it manually
	// instead of letting them retry a scrape that can never succeed.
	ErrorCodeUnsupported = "unsupported_site"

	defaultDedupeWindow    = 10 * time.Minute
	defaultRecentWindow    = 24 * time.Hour
	defaultLeaseTimeout    = 2 * time.Minute
	defaultMaxAttempts     = 3
	defaultClaimBatchLimit = 1
	defaultDrainLimit      = 20
	// dispatchTimeout bounds the detached Cloud Tasks enqueue RPC kicked off after
	// a new import is created (it runs off the request path).
	dispatchTimeout = 10 * time.Second
)

type WishlistService interface {
	GetByID(ctx context.Context, id string) (wishlistdomain.Wishlist, error)
	AddItem(ctx context.Context, wishlistID string, input *wishlistapp.AddItemInput) (wishlistdomain.WishlistItem, error)
}

type Scraper interface {
	Scrape(ctx context.Context, rawURL string, targetCurrencyCode string) (scrapeapp.Product, error)
	// ScrapeImport is the import path: it reports progress AND fires the paid
	// ZenRows backstop on a non-auto_complete outcome (when configured).
	ScrapeImport(
		ctx context.Context,
		rawURL string,
		targetCurrencyCode string,
		reporter scrapeapp.ProgressReporter,
	) (scrapeapp.Product, error)
}

// Dispatcher hands a freshly-enqueued import off to be processed out-of-band
// (Cloud Tasks -> the scraper service's process route). It is optional: when nil
// (local/all role) the in-process poller drains the queue instead. A dispatch
// failure must never fail the enqueue — the import-drain Job recovers the job.
type Dispatcher interface {
	Dispatch(ctx context.Context, jobID string) error
}

type Service struct {
	logger       *slog.Logger
	repo         ports.Repository
	wishlists    WishlistService
	scraper      Scraper
	dispatcher   Dispatcher
	resolver     scrapeapp.HostResolver
	nowFn        func() time.Time
	dedupeWindow time.Duration
	recentWindow time.Duration
	leaseTimeout time.Duration
	maxAttempts  int
}

type CreateJobInput struct {
	WishlistID         string
	SharedText         string
	ClientRequestID    string
	TargetCurrencyCode string
}

type ListJobsInput struct {
	Status string
	Limit  int
	Offset int
}

func NewService(logger *slog.Logger, repo ports.Repository, wishlists WishlistService, scraper Scraper, resolver scrapeapp.HostResolver) *Service {
	if resolver == nil {
		resolver = net.DefaultResolver
	}
	if logger == nil {
		logger = slog.Default()
	}
	return &Service{
		logger:       logger,
		repo:         repo,
		wishlists:    wishlists,
		scraper:      scraper,
		resolver:     resolver,
		nowFn:        time.Now,
		dedupeWindow: defaultDedupeWindow,
		recentWindow: defaultRecentWindow,
		leaseTimeout: defaultLeaseTimeout,
		maxAttempts:  defaultMaxAttempts,
	}
}

// WithDispatcher wires an out-of-band dispatcher (Cloud Tasks) used by the api
// role to hand new imports to the scraper service. Returns the service for
// chaining. Leaving it unset keeps the in-process poller as the drain path.
func (s *Service) WithDispatcher(d Dispatcher) *Service {
	s.dispatcher = d
	return s
}

func (s *Service) Create(ctx context.Context, input *CreateJobInput) (importdomain.Job, bool, error) {
	if input == nil {
		return importdomain.Job{}, false, ValidationError("input", "input is required")
	}
	user, ok := authctx.UserFromContext(ctx)
	if !ok || user.ID == "" {
		return importdomain.Job{}, false, ValidationError("authorization", "authorization is required")
	}
	clientRequestID := strings.TrimSpace(input.ClientRequestID)
	if clientRequestID == "" {
		return importdomain.Job{}, false, ValidationError("clientRequestId", "clientRequestId is required")
	}
	wishlistID := strings.TrimSpace(input.WishlistID)
	targetCurrency, err := scrapeapp.NormalizeCurrencyCode(input.TargetCurrencyCode)
	if err != nil {
		return importdomain.Job{}, false, err
	}
	rawURL := extractFirstURL(input.SharedText)
	if rawURL == "" {
		return importdomain.Job{}, false, ValidationError("sharedText", "shared text must contain a product URL")
	}
	normalizedURL, err := scrapeapp.NormalizeProductURL(ctx, s.resolver, rawURL)
	if err != nil {
		return importdomain.Job{}, false, err
	}

	var wishlistIDPtr *string
	if wishlistID != "" {
		wishlist, getErr := s.wishlists.GetByID(ctx, wishlistID)
		if getErr != nil {
			return importdomain.Job{}, false, getErr
		}
		if !canEditWishlist(user.ID, wishlist) {
			return importdomain.Job{}, false, wishlistapp.WishlistNotFound()
		}
		wishlistIDPtr = &wishlistID
	}

	job, existing, err := s.repo.CreateOrGet(ctx, ports.CreateJobParams{
		UserID:             user.ID,
		WishlistID:         wishlistIDPtr,
		ClientRequestID:    clientRequestID,
		NormalizedURL:      normalizedURL.String(),
		Domain:             normalizedURL.Hostname(),
		TargetCurrencyCode: targetCurrency,
	}, s.dedupeWindow)
	if err != nil {
		return importdomain.Job{}, false, err
	}

	// Only a brand-new pending job needs dispatch; an existing/deduped job is
	// already in flight. Dispatch failures are logged, not surfaced: the import
	// returns success and the import-drain Job recovers an undispatched job. The
	// Cloud Tasks RPC runs on a detached goroutine so its latency never blocks the
	// user's enqueue response; it uses a fresh context (the request ctx is canceled
	// once the response is written) with its own short timeout.
	if !existing && s.dispatcher != nil {
		jobID := job.ID
		dispatchCtx := context.WithoutCancel(ctx)
		go func() {
			ctx, cancel := context.WithTimeout(dispatchCtx, dispatchTimeout)
			defer cancel()
			if derr := s.dispatcher.Dispatch(ctx, jobID); derr != nil {
				s.logger.Warn("dispatch product import task failed", "job_id", jobID, "error", derr)
			}
		}()
	}

	return job, existing, nil
}

func (s *Service) List(ctx context.Context, input ListJobsInput) ([]importdomain.Job, error) {
	user, ok := authctx.UserFromContext(ctx)
	if !ok || user.ID == "" {
		return nil, ValidationError("authorization", "authorization is required")
	}
	limit := input.Limit
	if limit <= 0 || limit > 100 {
		limit = 25
	}
	offset := input.Offset
	if offset < 0 {
		offset = 0
	}
	var statuses []string
	if strings.TrimSpace(input.Status) != "" {
		status := strings.TrimSpace(input.Status)
		if !isKnownStatus(status) {
			return nil, ValidationError("status", "status is invalid")
		}
		statuses = []string{status}
	}
	return s.repo.List(ctx, ports.ListJobsParams{
		UserID:   user.ID,
		Statuses: statuses,
		Limit:    limit,
		Offset:   offset,
		Since:    s.nowFn().UTC().Add(-s.recentWindow),
	})
}

func (s *Service) Retry(ctx context.Context, id string) (importdomain.Job, error) {
	job, err := s.requireUserJob(ctx, id)
	if err != nil {
		return importdomain.Job{}, err
	}
	if !job.Retryable {
		return importdomain.Job{}, Conflict("retryable", "product import job is not retryable")
	}
	return s.repo.Retry(ctx, id)
}

func (s *Service) Acknowledge(ctx context.Context, id string) (importdomain.Job, error) {
	if _, err := s.requireUserJob(ctx, id); err != nil {
		return importdomain.Job{}, err
	}
	return s.repo.Acknowledge(ctx, id, s.nowFn().UTC())
}

func (s *Service) Assign(ctx context.Context, id string, wishlistID string) (importdomain.Job, error) {
	job, err := s.requireUserJob(ctx, id)
	if err != nil {
		return importdomain.Job{}, err
	}
	if job.Status != importdomain.StatusCompleted || job.WishlistID != nil || job.CreatedItemID != nil {
		return importdomain.Job{}, Conflict("status", "job is not an unassigned completed import")
	}
	wishlistID = strings.TrimSpace(wishlistID)
	if wishlistID == "" {
		return importdomain.Job{}, ValidationError("wishlistId", "wishlistId is required")
	}
	wishlist, err := s.wishlists.GetByID(ctx, wishlistID)
	if err != nil {
		return importdomain.Job{}, err
	}
	user, _ := authctx.UserFromContext(ctx)
	if !canEditWishlist(user.ID, wishlist) {
		return importdomain.Job{}, wishlistapp.WishlistNotFound()
	}
	itemCtx := authctx.WithUser(ctx, authctx.User{ID: job.UserID})
	item, err := s.wishlists.AddItem(itemCtx, wishlistID, &wishlistapp.AddItemInput{
		Title:      ptrOrEmpty(job.Title),
		PriceLabel: job.PriceLabel,
		ImageURL:   job.ImageURL,
		ProductURL: &job.NormalizedURL,
		Priority:   wishlistdomain.ItemPriorityMedium,
		Status:     wishlistdomain.ItemStatusSaved,
	})
	if err != nil {
		return importdomain.Job{}, err
	}
	return s.repo.Assign(ctx, job.ID, wishlistID, item.ID)
}

func (s *Service) RecoverStuck(ctx context.Context) error {
	released, failed, err := s.repo.ReleaseStuck(ctx, ports.ReleaseStuckParams{
		LeaseExpiredBefore: s.nowFn().UTC().Add(-s.leaseTimeout),
		MaxAttempts:        s.maxAttempts,
		RetryableErrorCode: ErrorCodeTimeout,
		TimeoutErrorCode:   ErrorCodeTimeout,
		FailedMessage:      "product import worker timed out",
	})
	if err == nil && (released > 0 || failed > 0) {
		s.logger.Warn("recovered stuck product import jobs", "released", released, "failed", failed)
	}
	return err
}

func (s *Service) ProcessNext(ctx context.Context) (bool, error) {
	if err := s.RecoverStuck(ctx); err != nil {
		return false, err
	}
	job, err := s.repo.ClaimNext(ctx, ports.ClaimParams{
		Now:         s.nowFn().UTC(),
		MaxAttempts: s.maxAttempts,
		Limit:       defaultClaimBatchLimit,
	})
	if errors.Is(err, ports.ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	started := s.nowFn()
	if err := s.processClaimed(ctx, job); err != nil {
		s.logger.Error("product import job processing failed", "job_id", job.ID, "domain", job.Domain, "error", err)
		return true, nil
	}
	s.logger.Info("product import job processed", "job_id", job.ID, "domain", job.Domain, "duration_ms", time.Since(started).Milliseconds())
	return true, nil
}

// ProcessByID claims and processes one specific job (the Cloud Tasks directed
// dispatch path on the scraper service). It is idempotent: a job that is absent
// or no longer pending (already processed, terminal, or a Cloud Tasks redelivery)
// is a successful no-op so the task is not retried. A non-nil error means the
// outcome could not be persisted — the caller returns non-2xx and Cloud Tasks
// retries. The needs_review/failed terminal rules are honored via processClaimed.
func (s *Service) ProcessByID(ctx context.Context, jobID string) error {
	job, err := s.repo.ClaimByID(ctx, strings.TrimSpace(jobID), s.nowFn().UTC())
	if errors.Is(err, ports.ErrNotFound) {
		s.logger.Info("product import job not claimable, skipping", "job_id", jobID)
		return nil
	}
	if err != nil {
		return err
	}
	started := s.nowFn()
	if err := s.processClaimed(ctx, job); err != nil {
		s.logger.Error("product import job processing failed", "job_id", job.ID, "domain", job.Domain, "error", err)
		// processClaimed only errors when the final Settle write failed, leaving the
		// row stuck in 'processing'. Release it back to pending so the Cloud Tasks
		// retry (triggered by the non-2xx below) re-claims it promptly via ClaimByID
		// instead of waiting for the lease-timeout sweep. Best-effort: if this also
		// fails, ReleaseStuck still recovers the row. A re-process re-runs scrape +
		// AddItem; that duplicate-item risk exists on every recovery path and is out
		// of scope here.
		if relErr := s.repo.ReleaseToPending(ctx, job.ID); relErr != nil {
			s.logger.Warn("release product import job to pending failed", "job_id", job.ID, "error", relErr)
		}
		return err
	}
	s.logger.Info(
		"product import job processed",
		"job_id", job.ID, "domain", job.Domain, "duration_ms", time.Since(started).Milliseconds(),
	)
	return nil
}

// DrainPending processes up to limit pending jobs and returns how many it
// settled. It is the import-drain Job's entry point: each iteration reuses
// ProcessNext (RecoverStuck + ClaimNext + processClaimed), so it also recovers
// jobs whose Cloud Task was never created or whose scraper instance died
// mid-process. It stops early when the queue is empty.
func (s *Service) DrainPending(ctx context.Context, limit int) (int, error) {
	if limit <= 0 {
		limit = defaultDrainLimit
	}
	processed := 0
	for processed < limit {
		if ctx.Err() != nil {
			return processed, ctx.Err()
		}
		did, err := s.ProcessNext(ctx)
		if err != nil {
			return processed, err
		}
		if !did {
			break
		}
		processed++
	}
	return processed, nil
}

func (s *Service) processClaimed(ctx context.Context, job importdomain.Job) error {
	product, scrapeErr := s.scraper.ScrapeImport(
		ctx, job.NormalizedURL, job.TargetCurrencyCode, s.progressReporter(ctx, job.ID),
	)
	snap := snapshotFromProduct(product)

	outcome := resolveOutcome(snap, scrapeErr)

	if outcome.Status == importdomain.StatusCompleted && job.WishlistID != nil {
		if snap.Title == nil {
			// A completed verdict implies a HIGH (non-empty) name today, but guard
			// the deref so a future invariant break degrades to human review rather
			// than panicking the worker.
			outcome = needsReviewOutcome(outcome.Snapshot, "product title missing")
		} else {
			itemCtx := authctx.WithUser(ctx, authctx.User{ID: job.UserID})
			productURL := job.NormalizedURL
			if snap.CanonicalURL != "" {
				productURL = snap.CanonicalURL
			}
			item, createErr := s.wishlists.AddItem(itemCtx, *job.WishlistID, &wishlistapp.AddItemInput{
				Title:             *snap.Title,
				PriceLabel:        snap.PriceLabel,
				PriceAmount:       snap.PriceAmount,
				PriceCurrencyCode: snap.PriceCurrencyCode,
				ImageURL:          snap.ImageURL,
				ProductURL:        &productURL,
				Priority:          wishlistdomain.ItemPriorityMedium,
				Status:            wishlistdomain.ItemStatusSaved,
			})
			if createErr != nil {
				outcome = ports.JobOutcome{
					Status:    importdomain.StatusFailed,
					Snapshot:  outcome.Snapshot,
					LastError: createErr.Error(),
					ErrorCode: ErrorCodeItemCreate,
					Retryable: !isWishlistValidationError(createErr),
				}
			} else {
				outcome.CreatedItemID = &item.ID
			}
		}
	}

	_, err := s.repo.Settle(ctx, job.ID, outcome)
	return err
}

// progressReporter returns a monotonic, throttled reporter that persists scrape
// progress. The scrape orchestrator may call it from several goroutines, so it
// is mutex-guarded and only writes when the percent advances.
func (s *Service) progressReporter(ctx context.Context, jobID string) scrapeapp.ProgressReporter {
	var mu sync.Mutex
	lastPercent := -1
	return func(stage string, percent int) {
		mu.Lock()
		if percent <= lastPercent {
			mu.Unlock()
			return
		}
		lastPercent = percent
		mu.Unlock()
		if err := s.repo.UpdateProgress(ctx, jobID, stage, percent); err != nil {
			s.logger.Debug("update import progress failed", "job_id", jobID, "error", err.Error())
		}
	}
}

// needsReviewOutcome builds the terminal needs_review outcome. needs_review is a
// human-review state, not a transient failure: it is never retryable. ClaimNext
// re-claims only retryable rows, so a retryable needs_review would be re-scraped
// every backoff window — burning a ~30s render and flipping the job out of
// review until it hit max attempts. Centralizing it keeps that rule in one place.
func needsReviewOutcome(ps ports.ProductSnapshot, lastError string) ports.JobOutcome {
	return ports.JobOutcome{
		Status:    importdomain.StatusNeedsReview,
		Snapshot:  ps,
		LastError: lastError,
		ErrorCode: ErrorCodeIncomplete,
		Retryable: false,
	}
}

func resolveOutcome(snap productSnapshot, scrapeErr error) ports.JobOutcome {
	ps := ports.ProductSnapshot{
		Title:           snap.Title,
		PriceLabel:      snap.PriceLabel,
		PriceConfidence: snap.PriceConfidence,
		PriceSource:     snap.PriceSource,
		PriceWarnings:   snap.PriceWarnings,
		ImageURL:        snap.ImageURL,
		Completeness:    snap.Completeness,
	}
	if scrapeErr != nil {
		retryable, code := classifyScrapeError(scrapeErr)
		// A hard anti-bot block is terminal: never retry, never review — there is
		// no data and never will be. Tell the user the store is unsupported.
		if code == ErrorCodeUnsupported {
			return ports.JobOutcome{
				Status:    importdomain.StatusFailed,
				Snapshot:  ps,
				LastError: scrapeErr.Error(),
				ErrorCode: code,
				Retryable: false,
			}
		}
		if snap.Verdict == scrapeapp.VerdictNeedsReview || shouldNeedsReview(snap) {
			return needsReviewOutcome(ps, "product details need review")
		}
		return ports.JobOutcome{
			Status:    importdomain.StatusFailed,
			Snapshot:  ps,
			LastError: scrapeErr.Error(),
			ErrorCode: code,
			Retryable: retryable,
		}
	}

	// Primary path: the engine's verdict drives the status.
	switch snap.Verdict {
	case scrapeapp.VerdictAutoComplete:
		return ports.JobOutcome{Status: importdomain.StatusCompleted, Snapshot: ps}
	case scrapeapp.VerdictNeedsReview:
		return needsReviewOutcome(ps, reviewReason(snap))
	case scrapeapp.VerdictFailed:
		if shouldNeedsReview(snap) {
			return needsReviewOutcome(ps, "product details need review")
		}
		return ports.JobOutcome{
			Status:    importdomain.StatusFailed,
			Snapshot:  ps,
			LastError: "could not extract enough product details",
			ErrorCode: ErrorCodeIncomplete,
			Retryable: true,
		}
	}

	// Defensive fallback for products that carry no verdict (legacy/partial).
	if !isComplete(snap) {
		if shouldNeedsReview(snap) {
			return needsReviewOutcome(ps, "product details need review")
		}
		return ports.JobOutcome{
			Status:    importdomain.StatusFailed,
			Snapshot:  ps,
			LastError: "could not extract enough product details",
			ErrorCode: ErrorCodeIncomplete,
			Retryable: true,
		}
	}
	if !snap.HasTrustedPrice {
		return needsReviewOutcome(ps, "product price needs review")
	}
	return ports.JobOutcome{Status: importdomain.StatusCompleted, Snapshot: ps}
}

func reviewReason(snap productSnapshot) string {
	if len(snap.PriceWarnings) > 0 {
		return "product details need review: " + strings.Join(snap.PriceWarnings, ", ")
	}
	return "product details need review"
}

func (s *Service) requireUserJob(ctx context.Context, id string) (importdomain.Job, error) {
	user, ok := authctx.UserFromContext(ctx)
	if !ok || user.ID == "" {
		return importdomain.Job{}, ValidationError("authorization", "authorization is required")
	}
	job, err := s.repo.GetByID(ctx, strings.TrimSpace(id))
	if errors.Is(err, ports.ErrNotFound) {
		return importdomain.Job{}, NotFound()
	}
	if err != nil {
		return importdomain.Job{}, err
	}
	if job.UserID != user.ID {
		return importdomain.Job{}, NotFound()
	}
	return job, nil
}

type productSnapshot struct {
	Title             *string
	PriceLabel        *string
	PriceAmount       *string
	PriceCurrencyCode *string
	PriceConfidence   *string
	PriceSource       *string
	PriceWarnings     []string
	ImageURL          *string
	Completeness      int
	HasTrustedPrice   bool
	// Verdict is the engine's calibrated outcome — the primary driver of the
	// job status. Empty for legacy/partial products (falls back to the ladder).
	Verdict scrapeapp.Verdict
	// CanonicalURL is the cleaned product link; preferred for the created item.
	CanonicalURL string
}

func snapshotFromProduct(product scrapeapp.Product) productSnapshot {
	title := optional(product.Name)
	priceLabel := optional(strings.TrimSpace(strings.TrimSpace(product.PriceCurrency) + " " + strings.TrimSpace(product.PriceAmount)))
	priceAmount := optionalAmount(product.PriceAmount)
	priceCurrencyCode := optionalCurrencyCode(product.PriceCurrency)
	priceConfidence := optional(product.PriceConfidence)
	priceSource := optional(product.PriceSource)
	priceWarnings := append([]string(nil), product.PriceWarnings...)
	imageURL := optional(product.ImageURL)
	completeness := 0
	if title != nil {
		completeness++
	}
	if priceLabel != nil {
		completeness++
	}
	if imageURL != nil {
		completeness++
	}
	return productSnapshot{
		Title:             title,
		PriceLabel:        priceLabel,
		PriceAmount:       priceAmount,
		PriceCurrencyCode: priceCurrencyCode,
		PriceConfidence:   priceConfidence,
		PriceSource:       priceSource,
		PriceWarnings:     priceWarnings,
		ImageURL:          imageURL,
		Completeness:      completeness,
		HasTrustedPrice:   priceLabel != nil && product.HasHighConfidencePrice(),
		Verdict:           product.Verdict,
		CanonicalURL:      strings.TrimSpace(product.CanonicalURL),
	}
}

func isComplete(snapshot productSnapshot) bool {
	return snapshot.Title != nil && snapshot.PriceLabel != nil && snapshot.ImageURL != nil
}

func shouldNeedsReview(snapshot productSnapshot) bool {
	return snapshot.Completeness >= 2
}

func classifyScrapeError(err error) (retryable bool, code string) {
	if errors.Is(err, context.DeadlineExceeded) {
		return true, ErrorCodeTimeout
	}
	if appErr, ok := scrapeapp.AsError(err); ok {
		switch appErr.Code {
		case scrapeapp.ErrorCodeTimeout:
			return true, ErrorCodeTimeout
		case scrapeapp.ErrorCodeBadRequest:
			return false, string(appErr.Code)
		case scrapeapp.ErrorCodeUnsupported:
			return false, ErrorCodeUnsupported
		default:
			return true, string(appErr.Code)
		}
	}
	return true, ErrorCodeTransientScrape
}

func isWishlistValidationError(err error) bool {
	appErr, ok := wishlistapp.AsError(err)
	return ok && appErr.Code == wishlistapp.ErrorCodeValidation
}

func canEditWishlist(userID string, wishlist wishlistdomain.Wishlist) bool {
	if wishlist.OwnerID == userID {
		return true
	}
	for _, member := range wishlist.Members {
		if member.UserID == userID && member.Role == wishlistdomain.MemberRoleEditor {
			return true
		}
	}
	return false
}

func isKnownStatus(status string) bool {
	switch status {
	case importdomain.StatusPending, importdomain.StatusProcessing, importdomain.StatusCompleted, importdomain.StatusNeedsReview, importdomain.StatusFailed:
		return true
	default:
		return false
	}
}

func extractFirstURL(text string) string {
	match := urlPattern.FindString(strings.TrimSpace(text))
	if match == "" {
		return ""
	}
	return strings.TrimRight(match, ".,);]")
}

func ptrOrEmpty(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func optional(value string) *string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

var (
	priceAmountPattern  = regexp.MustCompile(`^\d+(\.\d+)?$`)
	currencyCodePattern = regexp.MustCompile(`^[A-Z]{3}$`)
)

// optionalAmount returns a clean decimal string suitable for the NUMERIC
// price_amount column, or nil when the value is absent or non-numeric.
func optionalAmount(value string) *string {
	trimmed := strings.TrimSpace(value)
	if !priceAmountPattern.MatchString(trimmed) {
		return nil
	}
	return &trimmed
}

// optionalCurrencyCode normalizes to an uppercase ISO-4217 code matching the
// price_currency_code CHECK, or nil when absent or malformed.
func optionalCurrencyCode(value string) *string {
	code := strings.ToUpper(strings.TrimSpace(value))
	if !currencyCodePattern.MatchString(code) {
		return nil
	}
	return &code
}

var urlPattern = regexp.MustCompile(`https?://\S+`)
