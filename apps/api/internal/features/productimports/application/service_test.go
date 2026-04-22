package application

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	importdomain "github.com/danielrispler/wishiz/apps/api/internal/features/productimports/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/features/productimports/ports"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	wishlistapp "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/application"
	wishlistdomain "github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/domain"
)

func TestServiceMarksNeedsReviewWhenScrapeReturnsTwoFields(t *testing.T) {
	t.Parallel()

	repo := &fakeRepo{
		claimedJob: productImportJob(),
	}
	service := NewService(
		testLogger(),
		repo,
		&fakeWishlistService{},
		fakeScraper{
			product: scrapeapp.Product{
				Name:     "Desk lamp",
				ImageURL: "https://example.com/lamp.png",
			},
			err: scrapeapp.ScrapeFailed("could not extract complete product details"),
		},
		nil,
	)

	processed, err := service.ProcessNext(context.Background())
	if err != nil {
		t.Fatalf("process next: %v", err)
	}
	if !processed {
		t.Fatalf("expected a job to be processed")
	}
	if repo.needsReview == nil {
		t.Fatalf("expected job to be marked needs_review")
	}
	if repo.needsReview.Completeness != 2 || value(repo.needsReview.Title) != "Desk lamp" || value(repo.needsReview.ImageURL) == "" {
		t.Fatalf("unexpected needs review snapshot: %+v", repo.needsReview)
	}
	if !repo.needsReview.Retryable {
		t.Fatalf("expected needs_review job to be retryable")
	}
}

func TestServiceCompletesJobAndCreatesWishlistItem(t *testing.T) {
	t.Parallel()

	repo := &fakeRepo{
		claimedJob: productImportJob(),
	}
	wishlists := &fakeWishlistService{}
	service := NewService(
		testLogger(),
		repo,
		wishlists,
		fakeScraper{
			product: scrapeapp.Product{
				Name:            "Desk lamp",
				PriceAmount:     "40.00",
				PriceCurrency:   "USD",
				PriceConfidence: scrapeapp.PriceConfidenceHigh,
				PriceSource:     scrapeapp.PriceSourceJSONLD,
				ImageURL:        "https://example.com/lamp.png",
			},
		},
		nil,
	)

	processed, err := service.ProcessNext(context.Background())
	if err != nil {
		t.Fatalf("process next: %v", err)
	}
	if !processed {
		t.Fatalf("expected a job to be processed")
	}
	if repo.completed == nil {
		t.Fatalf("expected job to be completed")
	}
	if repo.completed.CreatedItemID != "item-1" || repo.completed.PriceLabel != "USD 40.00" {
		t.Fatalf("unexpected completed params: %+v", repo.completed)
	}
	if wishlists.added == nil || wishlists.added.Title != "Desk lamp" {
		t.Fatalf("expected wishlist item creation, got %+v", wishlists.added)
	}
}

func TestServiceMarksNeedsReviewWhenPriceIsNotHighConfidence(t *testing.T) {
	t.Parallel()

	repo := &fakeRepo{
		claimedJob: productImportJob(),
	}
	wishlists := &fakeWishlistService{}
	service := NewService(
		testLogger(),
		repo,
		wishlists,
		fakeScraper{
			product: scrapeapp.Product{
				Name:            "Desk lamp",
				PriceAmount:     "10.00",
				PriceCurrency:   "USD",
				PriceConfidence: scrapeapp.PriceConfidenceSuspicious,
				PriceSource:     scrapeapp.PriceSourceSelector,
				PriceWarnings:   []string{scrapeapp.PriceWarningNonPrimaryContext},
				ImageURL:        "https://example.com/lamp.png",
			},
		},
		nil,
	)

	processed, err := service.ProcessNext(context.Background())
	if err != nil {
		t.Fatalf("process next: %v", err)
	}
	if !processed {
		t.Fatalf("expected a job to be processed")
	}
	if repo.needsReview == nil {
		t.Fatalf("expected job to be marked needs_review")
	}
	if repo.needsReview.PriceConfidence == nil || *repo.needsReview.PriceConfidence != scrapeapp.PriceConfidenceSuspicious {
		t.Fatalf("expected suspicious confidence, got %+v", repo.needsReview)
	}
	if repo.completed != nil || wishlists.added != nil {
		t.Fatalf("expected no item creation, completed=%+v added=%+v", repo.completed, wishlists.added)
	}
}

func productImportJob() importdomain.Job {
	return importdomain.Job{
		ID:                 "job-1",
		UserID:             "user-1",
		WishlistID:         "wishlist-1",
		NormalizedURL:      "https://example.com/lamp",
		Domain:             "example.com",
		TargetCurrencyCode: "USD",
		Status:             importdomain.StatusProcessing,
		AttemptCount:       1,
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}
}

type fakeRepo struct {
	claimedJob  importdomain.Job
	completed   *ports.CompleteJobParams
	needsReview *ports.NeedsReviewJobParams
}

func (r *fakeRepo) CreateOrGet(context.Context, ports.CreateJobParams, time.Duration) (importdomain.Job, bool, error) {
	return importdomain.Job{}, false, nil
}

func (r *fakeRepo) List(context.Context, ports.ListJobsParams) ([]importdomain.Job, error) {
	return nil, nil
}

func (r *fakeRepo) GetByID(context.Context, string) (importdomain.Job, error) {
	return importdomain.Job{}, ports.ErrNotFound
}

func (r *fakeRepo) Retry(context.Context, string) (importdomain.Job, error) {
	return importdomain.Job{}, nil
}

func (r *fakeRepo) Acknowledge(context.Context, string, time.Time) (importdomain.Job, error) {
	return importdomain.Job{}, nil
}

func (r *fakeRepo) ReleaseStuck(context.Context, ports.ReleaseStuckParams) (int64, int64, error) {
	return 0, 0, nil
}

func (r *fakeRepo) ClaimNext(context.Context, ports.ClaimParams) (importdomain.Job, error) {
	return r.claimedJob, nil
}

func (r *fakeRepo) MarkCompleted(_ context.Context, params ports.CompleteJobParams) (importdomain.Job, error) {
	r.completed = &params
	return r.claimedJob, nil
}

func (r *fakeRepo) MarkNeedsReview(_ context.Context, params ports.NeedsReviewJobParams) (importdomain.Job, error) {
	r.needsReview = &params
	return r.claimedJob, nil
}

func (r *fakeRepo) MarkFailed(context.Context, ports.FailJobParams) (importdomain.Job, error) {
	return r.claimedJob, nil
}

type fakeScraper struct {
	product scrapeapp.Product
	err     error
}

func (s fakeScraper) Scrape(context.Context, string, string) (scrapeapp.Product, error) {
	return s.product, s.err
}

type fakeWishlistService struct {
	added *wishlistapp.AddItemInput
}

func (s fakeWishlistService) GetByID(context.Context, string) (wishlistdomain.Wishlist, error) {
	return wishlistdomain.Wishlist{ID: "wishlist-1", OwnerID: "user-1"}, nil
}

func (s *fakeWishlistService) AddItem(_ context.Context, _ string, input *wishlistapp.AddItemInput) (wishlistdomain.WishlistItem, error) {
	s.added = input
	return wishlistdomain.WishlistItem{ID: "item-1"}, nil
}

func testLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func value(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
