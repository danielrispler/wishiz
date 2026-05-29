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
	if repo.settled.Status != importdomain.StatusNeedsReview {
		t.Fatalf("expected job to be marked needs_review, got %q", repo.settled.Status)
	}
	if repo.settled.Snapshot.Completeness != 2 || value(repo.settled.Snapshot.Title) != "Desk lamp" || value(repo.settled.Snapshot.ImageURL) == "" {
		t.Fatalf("unexpected needs review snapshot: %+v", repo.settled.Snapshot)
	}
	if !repo.settled.Retryable {
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
	if repo.settled.Status != importdomain.StatusCompleted {
		t.Fatalf("expected job to be completed, got %q", repo.settled.Status)
	}
	if value(repo.settled.CreatedItemID) != "item-1" || value(repo.settled.Snapshot.PriceLabel) != "USD 40.00" {
		t.Fatalf("unexpected completed outcome: %+v", repo.settled)
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
	if repo.settled.Status != importdomain.StatusNeedsReview {
		t.Fatalf("expected job to be marked needs_review, got %q", repo.settled.Status)
	}
	if repo.settled.Snapshot.PriceConfidence == nil || *repo.settled.Snapshot.PriceConfidence != scrapeapp.PriceConfidenceSuspicious {
		t.Fatalf("expected suspicious confidence, got %+v", repo.settled.Snapshot)
	}
	if wishlists.added != nil {
		t.Fatalf("expected no item creation, added=%+v", wishlists.added)
	}
}

func TestResolveOutcome(t *testing.T) {
	t.Parallel()

	str := func(s string) *string { return &s }

	partialSnap := productSnapshot{
		Title:        str("Lamp"),
		ImageURL:     str("https://img"),
		Completeness: 2,
	}
	thinSnap := productSnapshot{
		Title:        str("Lamp"),
		Completeness: 1,
	}
	completeUntrusted := productSnapshot{
		Title:        str("Lamp"),
		PriceLabel:   str("USD 10"),
		ImageURL:     str("https://img"),
		Completeness: 3,
	}
	completeTrusted := productSnapshot{
		Title:           str("Lamp"),
		PriceLabel:      str("USD 10"),
		ImageURL:        str("https://img"),
		Completeness:    3,
		HasTrustedPrice: true,
	}

	cases := []struct {
		name          string
		snap          productSnapshot
		scrapeErr     error
		wantStatus    string
		wantRetryable bool
	}{
		{
			name:          "scrape error partial → needs_review retryable",
			snap:          partialSnap,
			scrapeErr:     scrapeapp.ScrapeFailed("boom"),
			wantStatus:    importdomain.StatusNeedsReview,
			wantRetryable: true,
		},
		{
			name:          "scrape error insufficient → failed retryable",
			snap:          thinSnap,
			scrapeErr:     scrapeapp.ScrapeFailed("boom"),
			wantStatus:    importdomain.StatusFailed,
			wantRetryable: true,
		},
		{
			name:          "bad request partial → needs_review not retryable",
			snap:          partialSnap,
			scrapeErr:     scrapeapp.BadRequest("blocked"),
			wantStatus:    importdomain.StatusNeedsReview,
			wantRetryable: false,
		},
		{
			name:          "no error incomplete partial → needs_review retryable",
			snap:          partialSnap,
			wantStatus:    importdomain.StatusNeedsReview,
			wantRetryable: true,
		},
		{
			name:          "no error incomplete insufficient → failed retryable",
			snap:          thinSnap,
			wantStatus:    importdomain.StatusFailed,
			wantRetryable: true,
		},
		{
			name:          "complete untrusted price → needs_review retryable",
			snap:          completeUntrusted,
			wantStatus:    importdomain.StatusNeedsReview,
			wantRetryable: true,
		},
		{
			name:       "complete trusted price → completed",
			snap:       completeTrusted,
			wantStatus: importdomain.StatusCompleted,
		},
		{
			name:       "completed CreatedItemID is nil",
			snap:       completeTrusted,
			wantStatus: importdomain.StatusCompleted,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			outcome := resolveOutcome(tc.snap, tc.scrapeErr)
			if outcome.Status != tc.wantStatus {
				t.Errorf("status: got %q, want %q", outcome.Status, tc.wantStatus)
			}
			if outcome.Status != importdomain.StatusCompleted && outcome.Retryable != tc.wantRetryable {
				t.Errorf("retryable: got %v, want %v", outcome.Retryable, tc.wantRetryable)
			}
			if outcome.Status == importdomain.StatusCompleted && outcome.CreatedItemID != nil {
				t.Errorf("CreatedItemID should be nil from resolveOutcome")
			}
		})
	}
}

func productImportJob() importdomain.Job {
	wishlistID := "wishlist-1"
	return importdomain.Job{
		ID:                 "job-1",
		UserID:             "user-1",
		WishlistID:         &wishlistID,
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
	claimedJob importdomain.Job
	settled    ports.JobOutcome
	settledID  string
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

func (r *fakeRepo) Settle(_ context.Context, id string, outcome ports.JobOutcome) (importdomain.Job, error) {
	r.settledID = id
	r.settled = outcome
	return r.claimedJob, nil
}

func (r *fakeRepo) Assign(context.Context, string, string, string) (importdomain.Job, error) {
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
