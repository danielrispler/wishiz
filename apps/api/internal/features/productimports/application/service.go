package application

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/url"
	"regexp"
	"strings"
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

	defaultDedupeWindow    = 10 * time.Minute
	defaultRecentWindow    = 24 * time.Hour
	defaultLeaseTimeout    = 2 * time.Minute
	defaultMaxAttempts     = 3
	defaultClaimBatchLimit = 1
)

type WishlistService interface {
	GetByID(ctx context.Context, id string) (wishlistdomain.Wishlist, error)
	AddItem(ctx context.Context, wishlistID string, input *wishlistapp.AddItemInput) (wishlistdomain.WishlistItem, error)
}

type Scraper interface {
	Scrape(ctx context.Context, rawURL string, targetCurrencyCode string) (scrapeapp.Product, error)
}

type Service struct {
	logger       *slog.Logger
	repo         ports.Repository
	wishlists    WishlistService
	scraper      Scraper
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
		wishlist, err := s.wishlists.GetByID(ctx, wishlistID)
		if err != nil {
			return importdomain.Job{}, false, err
		}
		if !canEditWishlist(user.ID, wishlist) {
			return importdomain.Job{}, false, wishlistapp.WishlistNotFound()
		}
		wishlistIDPtr = &wishlistID
	}

	return s.repo.CreateOrGet(ctx, ports.CreateJobParams{
		UserID:             user.ID,
		WishlistID:         wishlistIDPtr,
		ClientRequestID:    clientRequestID,
		NormalizedURL:      normalizedURL.String(),
		Domain:             normalizedURL.Hostname(),
		TargetCurrencyCode: targetCurrency,
	}, s.dedupeWindow)
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

func (s *Service) processClaimed(ctx context.Context, job importdomain.Job) error {
	product, err := s.scraper.Scrape(ctx, job.NormalizedURL, job.TargetCurrencyCode)
	snapshot := snapshotFromProduct(product)
	if err != nil {
		retryable, code := classifyScrapeError(err)
		if shouldNeedsReview(snapshot) {
			_, markErr := s.repo.MarkNeedsReview(ctx, ports.NeedsReviewJobParams{
				ID:              job.ID,
				Title:           snapshot.Title,
				PriceLabel:      snapshot.PriceLabel,
				PriceConfidence: snapshot.PriceConfidence,
				PriceSource:     snapshot.PriceSource,
				PriceWarnings:   snapshot.PriceWarnings,
				ImageURL:        snapshot.ImageURL,
				Completeness:    snapshot.Completeness,
				LastError:       "product details need review",
				ErrorCode:       ErrorCodeIncomplete,
				Retryable:       code != string(scrapeapp.ErrorCodeBadRequest),
			})
			return markErr
		}
		_, markErr := s.repo.MarkFailed(ctx, ports.FailJobParams{
			ID:              job.ID,
			Title:           snapshot.Title,
			PriceLabel:      snapshot.PriceLabel,
			PriceConfidence: snapshot.PriceConfidence,
			PriceSource:     snapshot.PriceSource,
			PriceWarnings:   snapshot.PriceWarnings,
			ImageURL:        snapshot.ImageURL,
			Completeness:    snapshot.Completeness,
			LastError:       err.Error(),
			ErrorCode:       code,
			Retryable:       retryable,
		})
		return markErr
	}
	if !isComplete(snapshot) {
		if shouldNeedsReview(snapshot) {
			_, markErr := s.repo.MarkNeedsReview(ctx, ports.NeedsReviewJobParams{
				ID:              job.ID,
				Title:           snapshot.Title,
				PriceLabel:      snapshot.PriceLabel,
				PriceConfidence: snapshot.PriceConfidence,
				PriceSource:     snapshot.PriceSource,
				PriceWarnings:   snapshot.PriceWarnings,
				ImageURL:        snapshot.ImageURL,
				Completeness:    snapshot.Completeness,
				LastError:       "product details need review",
				ErrorCode:       ErrorCodeIncomplete,
				Retryable:       true,
			})
			return markErr
		}
		_, markErr := s.repo.MarkFailed(ctx, ports.FailJobParams{
			ID:              job.ID,
			Title:           snapshot.Title,
			PriceLabel:      snapshot.PriceLabel,
			PriceConfidence: snapshot.PriceConfidence,
			PriceSource:     snapshot.PriceSource,
			PriceWarnings:   snapshot.PriceWarnings,
			ImageURL:        snapshot.ImageURL,
			Completeness:    snapshot.Completeness,
			LastError:       "could not extract enough product details",
			ErrorCode:       ErrorCodeIncomplete,
			Retryable:       true,
		})
		return markErr
	}
	if !snapshot.HasTrustedPrice {
		_, markErr := s.repo.MarkNeedsReview(ctx, ports.NeedsReviewJobParams{
			ID:              job.ID,
			Title:           snapshot.Title,
			PriceLabel:      snapshot.PriceLabel,
			PriceConfidence: snapshot.PriceConfidence,
			PriceSource:     snapshot.PriceSource,
			PriceWarnings:   snapshot.PriceWarnings,
			ImageURL:        snapshot.ImageURL,
			Completeness:    snapshot.Completeness,
			LastError:       "product price needs review",
			ErrorCode:       ErrorCodeIncomplete,
			Retryable:       true,
		})
		return markErr
	}

	var createdItemID *string
	if job.WishlistID != nil {
		itemCtx := authctx.WithUser(ctx, authctx.User{ID: job.UserID})
		item, createErr := s.wishlists.AddItem(itemCtx, *job.WishlistID, &wishlistapp.AddItemInput{
			Title:      *snapshot.Title,
			PriceLabel: snapshot.PriceLabel,
			ImageURL:   snapshot.ImageURL,
			ProductURL: &job.NormalizedURL,
			Priority:   wishlistdomain.ItemPriorityMedium,
			Status:     wishlistdomain.ItemStatusSaved,
		})
		if createErr != nil {
			retryable := !isWishlistValidationError(createErr)
			_, markErr := s.repo.MarkFailed(ctx, ports.FailJobParams{
				ID:              job.ID,
				Title:           snapshot.Title,
				PriceLabel:      snapshot.PriceLabel,
				PriceConfidence: snapshot.PriceConfidence,
				PriceSource:     snapshot.PriceSource,
				PriceWarnings:   snapshot.PriceWarnings,
				ImageURL:        snapshot.ImageURL,
				Completeness:    snapshot.Completeness,
				LastError:       createErr.Error(),
				ErrorCode:       ErrorCodeItemCreate,
				Retryable:       retryable,
			})
			return markErr
		}
		createdItemID = &item.ID
	}
	_, markErr := s.repo.MarkCompleted(ctx, ports.CompleteJobParams{
		ID:              job.ID,
		Title:           *snapshot.Title,
		PriceLabel:      *snapshot.PriceLabel,
		PriceConfidence: snapshot.PriceConfidence,
		PriceSource:     snapshot.PriceSource,
		PriceWarnings:   snapshot.PriceWarnings,
		ImageURL:        *snapshot.ImageURL,
		Completeness:    snapshot.Completeness,
		CreatedItemID:   createdItemID,
	})
	return markErr
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
	Title           *string
	PriceLabel      *string
	PriceConfidence *string
	PriceSource     *string
	PriceWarnings   []string
	ImageURL        *string
	Completeness    int
	HasTrustedPrice bool
}

func snapshotFromProduct(product scrapeapp.Product) productSnapshot {
	title := optional(product.Name)
	priceLabel := optional(strings.TrimSpace(strings.TrimSpace(product.PriceCurrency) + " " + strings.TrimSpace(product.PriceAmount)))
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
		Title:           title,
		PriceLabel:      priceLabel,
		PriceConfidence: priceConfidence,
		PriceSource:     priceSource,
		PriceWarnings:   priceWarnings,
		ImageURL:        imageURL,
		Completeness:    completeness,
		HasTrustedPrice: priceLabel != nil && product.HasHighConfidencePrice(),
	}
}

func isComplete(snapshot productSnapshot) bool {
	return snapshot.Title != nil && snapshot.PriceLabel != nil && snapshot.ImageURL != nil
}

func shouldNeedsReview(snapshot productSnapshot) bool {
	return snapshot.Completeness >= 2
}

func classifyScrapeError(err error) (bool, string) {
	if errors.Is(err, context.DeadlineExceeded) {
		return true, ErrorCodeTimeout
	}
	if appErr, ok := scrapeapp.AsError(err); ok {
		switch appErr.Code {
		case scrapeapp.ErrorCodeTimeout:
			return true, ErrorCodeTimeout
		case scrapeapp.ErrorCodeBadRequest:
			return false, string(appErr.Code)
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

func domainFromURL(rawURL string) string {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return parsed.Hostname()
}

var urlPattern = regexp.MustCompile(`https?://[^\s]+`)
