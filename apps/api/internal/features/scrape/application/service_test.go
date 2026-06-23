package application

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"sync/atomic"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

const autoCompleteHTML = `<html><head>
	<script type="application/ld+json">{"@type":"Product","name":"Desk Lamp","image":"https://x/lamp.png",
		"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script></head><body></body></html>`

const partialHTML = `<html><head><meta property="og:title" content="Desk Lamp"></head><body></body></html>`

func testService(t *testing.T, static, render Fetcher, probe CandidateSource, converter PriceConverter) *Service {
	t.Helper()
	return NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		NewEngine(EngineConfig{}),
		static, render, probe, publicResolver(), converter,
		ServiceConfig{Budget: 5 * time.Second, MaxConcurrentRenders: 2},
	)
}

func TestServiceAutoCompletesFromStaticAndEarlyAbortsRender(t *testing.T) {
	t.Parallel()

	var rendered atomic.Bool
	static := fakeFetcher{result: FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"}}
	render := blockingFetcher{canceled: &rendered}

	product, err := testService(t, static, render, nil, nil).
		Scrape(context.Background(), "https://shop.example/p", "USD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.Verdict != VerdictAutoComplete || product.Name != "Desk Lamp" {
		t.Fatalf("expected auto_complete from static, got %+v", product)
	}
	if !rendered.Load() {
		t.Fatalf("expected render to be early-aborted (ctx canceled)")
	}
}

func TestServiceEarlyAbortReturnsGateResultNotRereconcile(t *testing.T) {
	t.Parallel()

	// The render is guaranteed to add a CONFLICTING authoritative price, but only
	// after the cheap sources have already cleared the auto-complete gate. The
	// returned product must be the gate's verdict (auto_complete, price 40), not a
	// second reconciliation that folds in the late render candidate (price 99) and
	// flips the price to a conflict. One reconcile per outcome path → deterministic.
	const conflictRenderHTML = `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Desk Lamp","image":"https://x/lamp.png",
			"offers":{"@type":"Offer","price":"99","priceCurrency":"USD"}}</script></head><body></body></html>`

	started := make(chan struct{})
	static := gatedFetcher{
		result:    FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"},
		afterPeer: started,
	}
	render := lateConflictFetcher{
		result:  FetchResult{HTML: conflictRenderHTML, FinalURL: "https://shop.example/p"},
		started: started,
	}

	product, err := testService(t, static, render, nil, nil).
		Scrape(context.Background(), "https://shop.example/p", "USD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.Verdict != VerdictAutoComplete || product.PriceAmount != "40" {
		t.Fatalf("expected gate auto_complete (price 40), got verdict=%q price=%q",
			product.Verdict, product.PriceAmount)
	}
}

func TestServiceWaitsForRenderWhenStaticInsufficient(t *testing.T) {
	t.Parallel()

	static := fakeFetcher{result: FetchResult{HTML: partialHTML, FinalURL: "https://shop.example/p"}}
	render := fakeFetcher{result: FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"}}

	product, err := testService(t, static, render, nil, nil).
		Scrape(context.Background(), "https://shop.example/p", "USD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.Verdict != VerdictAutoComplete || product.PriceAmount != "40" {
		t.Fatalf("expected render to complete the product, got %+v", product)
	}
}

func TestServiceReportsUnsupportedOnAntiBotBlock(t *testing.T) {
	t.Parallel()

	const blockHTML = `<html><head><title>Access Denied</title></head>` +
		`<body>You don't have permission. Reference #18.abc</body></html>`
	render := fakeFetcher{result: FetchResult{HTML: blockHTML, FinalURL: "https://shop.example/p"}}

	_, err := testService(t, nil, render, nil, nil).
		Scrape(context.Background(), "https://shop.example/p", "USD")
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeUnsupported {
		t.Fatalf("expected unsupported error, got %v", err)
	}
}

func TestServiceRejectsPrivateHost(t *testing.T) {
	t.Parallel()

	_, err := testService(t, fakeFetcher{}, fakeFetcher{}, nil, nil).
		Scrape(context.Background(), "http://127.0.0.1/private", "USD")
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeBadRequest {
		t.Fatalf("expected bad request, got %v", err)
	}
}

func TestServiceConvertsPrice(t *testing.T) {
	t.Parallel()

	static := fakeFetcher{result: FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"}}
	converter := stubConverter{amount: "144.00", currency: "ILS"}

	product, err := testService(t, static, nil, nil, converter).
		Scrape(context.Background(), "https://shop.example/p", "ILS")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.PriceAmount != "144.00" || product.PriceCurrency != "ILS" {
		t.Fatalf("expected converted price, got %+v", product)
	}
}

func TestServiceDowngradesOnConversionFailure(t *testing.T) {
	t.Parallel()

	static := fakeFetcher{result: FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"}}
	converter := stubConverter{failFrom: "USD"}

	product, err := testService(t, static, nil, nil, converter).
		Scrape(context.Background(), "https://shop.example/p", "ILS")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.PriceAmount != "40" || product.PriceCurrency != "USD" {
		t.Fatalf("expected original price kept, got %+v", product)
	}
	if product.Verdict == VerdictAutoComplete {
		t.Fatalf("unconverted price must not auto_complete")
	}
	if !containsStr(product.PriceWarnings, "currency_unconverted") {
		t.Fatalf("expected currency_unconverted warning, got %v", product.PriceWarnings)
	}
}

func TestServiceShopifyProbeContributes(t *testing.T) {
	t.Parallel()

	static := fakeFetcher{result: FetchResult{HTML: partialHTML, FinalURL: "https://store.example/products/lamp"}}
	probe := fakeProbe{candidates: []extractors.Candidate{
		{Field: extractors.FieldName, Value: "Probe Lamp", Source: extractors.SourceShopify},
		{Field: extractors.FieldImage, Value: "https://cdn/lamp.jpg", Source: extractors.SourceShopify},
		extractors.NewShopifyPriceCandidate("40", "USD"),
	}}

	product, err := testService(t, static, nil, probe, nil).
		Scrape(context.Background(), "https://store.example/products/lamp", "USD")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.Verdict != VerdictAutoComplete || product.Name != "Probe Lamp" {
		t.Fatalf("expected probe to complete the product, got %+v", product)
	}
}

func TestServiceTimesOutWhenNoData(t *testing.T) {
	t.Parallel()

	service := NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		NewEngine(EngineConfig{}),
		slowFetcher{}, nil, nil, publicResolver(), nil,
		ServiceConfig{Budget: 50 * time.Millisecond},
	)
	_, err := service.Scrape(context.Background(), "https://shop.example/p", "USD")
	appErr, ok := AsError(err)
	if !ok || appErr.Code != ErrorCodeTimeout {
		t.Fatalf("expected timeout, got %v", err)
	}
}

func TestServiceEmitsProgressStagesInOrder(t *testing.T) {
	t.Parallel()

	static := fakeFetcher{result: FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"}}
	var stages []string
	_, err := testService(t, static, nil, nil, nil).ScrapeWithProgress(
		context.Background(), "https://shop.example/p", "USD",
		func(stage string, _ int) { stages = append(stages, stage) },
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{StageValidating, StageExtracting, StageCrossChecking, StageDone}
	if len(stages) != len(want) {
		t.Fatalf("unexpected stages: %v", stages)
	}
	for i, stage := range want {
		if stages[i] != stage {
			t.Fatalf("stage %d = %q, want %q (all: %v)", i, stages[i], stage, stages)
		}
	}
}

// --- ZenRows backstop second pass ---

// needsReviewHTML extracts a name + image but no price → needs_review (reviewable
// but not auto-completable). The backstop's stronger HTML can rescue it.
const needsReviewHTML = `<html><head>
	<meta property="og:title" content="Backstop Lamp">
	<meta property="og:image" content="https://x/lamp.png"></head><body></body></html>`

// backstopAutoHTML is full JSON-LD (name agrees with the own data) → auto_complete.
const backstopAutoHTML = `<html><head>
	<script type="application/ld+json">{"@type":"Product","name":"Backstop Lamp","image":"https://x/lamp.png",
		"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script></head><body></body></html>`

// backstopConflictHTML disagrees on the name and adds a foreign-currency price →
// a consensus conflict. It must NOT degrade the own needs_review into failed.
const backstopConflictHTML = `<html><head>
	<script type="application/ld+json">{"@type":"Product","name":"Totally Different Product","image":"",
		"offers":{"@type":"Offer","price":"999","priceCurrency":"EUR"}}</script></head><body></body></html>`

func backstopService(t *testing.T, static Fetcher, backstop Backstop) *Service {
	t.Helper()
	return NewService(
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		NewEngine(EngineConfig{}),
		static, nil, nil, publicResolver(), nil,
		ServiceConfig{
			Budget: 5 * time.Second, MaxConcurrentRenders: 2,
			Backstop: backstop, BackstopTimeout: 2 * time.Second,
		},
	)
}

func TestBackstopSkippedWhenOwnAutoCompletes(t *testing.T) {
	t.Parallel()
	static := fakeFetcher{result: FetchResult{HTML: autoCompleteHTML, FinalURL: "https://shop.example/p"}}
	backstop := &fakeBackstop{result: FetchResult{HTML: backstopAutoHTML}}

	product, err := backstopService(t, static, backstop).
		ScrapeImport(context.Background(), "https://shop.example/p", "USD", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("verdict = %q, want auto_complete", product.Verdict)
	}
	if backstop.called.Load() {
		t.Fatal("backstop must NOT fire when the own pipeline already auto-completes")
	}
}

func TestBackstopRescuesNeedsReviewToAutoComplete(t *testing.T) {
	t.Parallel()
	static := fakeFetcher{result: FetchResult{HTML: needsReviewHTML, FinalURL: "https://shop.de/p"}}
	backstop := &fakeBackstop{result: FetchResult{HTML: backstopAutoHTML}}

	product, err := backstopService(t, static, backstop).
		ScrapeImport(context.Background(), "https://shop.de/p", "USD", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !backstop.called.Load() {
		t.Fatal("backstop should fire on a non-auto_complete own verdict")
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("verdict = %q, want backstop to rescue to auto_complete", product.Verdict)
	}
	if backstop.gotCountry != "de" {
		t.Fatalf("proxy_country = %q, want it pinned to the .de ccTLD", backstop.gotCountry)
	}
}

func TestBackstopErrorSoftFailsToOwnProduct(t *testing.T) {
	t.Parallel()
	static := fakeFetcher{result: FetchResult{HTML: needsReviewHTML, FinalURL: "https://shop.example/p"}}
	backstop := &fakeBackstop{err: errTest}

	product, err := backstopService(t, static, backstop).
		ScrapeImport(context.Background(), "https://shop.example/p", "USD", nil)
	if err != nil {
		t.Fatalf("backstop error must be soft-failed, not propagated: %v", err)
	}
	if !backstop.called.Load() {
		t.Fatal("backstop should have been attempted")
	}
	if product.Verdict != VerdictNeedsReview || product.Name != "Backstop Lamp" {
		t.Fatalf("want the own needs_review product preserved, got %+v", product)
	}
}

func TestBackstopNeverDegradesBelowOwnVerdict(t *testing.T) {
	t.Parallel()
	// A geo-priced / conflicting backstop must never drop needs_review → failed.
	static := fakeFetcher{result: FetchResult{HTML: needsReviewHTML, FinalURL: "https://shop.example/p"}}
	backstop := &fakeBackstop{result: FetchResult{HTML: backstopConflictHTML}}

	product, err := backstopService(t, static, backstop).
		ScrapeImport(context.Background(), "https://shop.example/p", "USD", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if product.Verdict == VerdictFailed {
		t.Fatalf("backstop conflict degraded the verdict to failed: %+v", product)
	}
	if !product.HasAnyData() {
		t.Fatal("expected the own product data to be preserved")
	}
}

func TestScrapeAndProgressDoNotFireBackstop(t *testing.T) {
	t.Parallel()
	// discover (and the synchronous /scrape route) use Scrape/ScrapeWithProgress —
	// neither path may ever incur the paid backstop.
	static := fakeFetcher{result: FetchResult{HTML: needsReviewHTML, FinalURL: "https://shop.example/p"}}

	scrapeBackstop := &fakeBackstop{result: FetchResult{HTML: backstopAutoHTML}}
	if _, err := backstopService(t, static, scrapeBackstop).
		Scrape(context.Background(), "https://shop.example/p", "USD"); err != nil {
		t.Fatalf("Scrape error: %v", err)
	}
	if scrapeBackstop.called.Load() {
		t.Fatal("Scrape (discover path) must NOT fire the backstop")
	}

	progressBackstop := &fakeBackstop{result: FetchResult{HTML: backstopAutoHTML}}
	if _, err := backstopService(t, static, progressBackstop).
		ScrapeWithProgress(context.Background(), "https://shop.example/p", "USD", nil); err != nil {
		t.Fatalf("ScrapeWithProgress error: %v", err)
	}
	if progressBackstop.called.Load() {
		t.Fatal("ScrapeWithProgress must NOT fire the backstop")
	}
}

// --- fakes ---

var errTest = errors.New("backstop boom")

type fakeBackstop struct {
	result     FetchResult
	err        error
	called     atomic.Bool
	gotCountry string
}

func (b *fakeBackstop) Fetch(_ context.Context, _, proxyCountry string) (FetchResult, error) {
	b.called.Store(true)
	b.gotCountry = proxyCountry
	return b.result, b.err
}

type fakeFetcher struct {
	result FetchResult
	err    error
}

func (f fakeFetcher) Fetch(context.Context, string) (FetchResult, error) {
	return f.result, f.err
}

type slowFetcher struct{}

func (slowFetcher) Fetch(ctx context.Context, _ string) (FetchResult, error) {
	<-ctx.Done()
	return FetchResult{}, ctx.Err()
}

type blockingFetcher struct {
	canceled *atomic.Bool
}

func (b blockingFetcher) Fetch(ctx context.Context, _ string) (FetchResult, error) {
	<-ctx.Done()
	b.canceled.Store(true)
	return FetchResult{}, ctx.Err()
}

// gatedFetcher returns its result only after afterPeer is closed, so the cheap
// path cannot finish (and clear the gate) until the render peer is parked in Fetch.
type gatedFetcher struct {
	result    FetchResult
	afterPeer chan struct{}
}

func (f gatedFetcher) Fetch(ctx context.Context, _ string) (FetchResult, error) {
	select {
	case <-f.afterPeer:
	case <-ctx.Done():
		return FetchResult{}, ctx.Err()
	}
	return f.result, nil
}

// lateConflictFetcher signals it is parked, blocks until the early-abort cancels
// it, then still returns real (conflicting) data so the service add()s it after
// the gate decision — deterministically exercising the double-reconcile hazard.
type lateConflictFetcher struct {
	result  FetchResult
	started chan struct{}
}

func (f lateConflictFetcher) Fetch(ctx context.Context, _ string) (FetchResult, error) {
	close(f.started)
	<-ctx.Done()
	return f.result, nil
}

type fakeProbe struct {
	candidates []extractors.Candidate
}

func (p fakeProbe) Candidates(context.Context, string) ([]extractors.Candidate, error) {
	return p.candidates, nil
}

func publicResolver() stubResolver {
	return stubResolver{addresses: []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}}}
}

type stubConverter struct {
	amount   string
	currency string
	failFrom string
}

func (s stubConverter) Convert(amount, fromCurrency, toCurrency string) (converted string, code string, err error) {
	if s.failFrom != "" && fromCurrency == s.failFrom {
		return "", "", &Error{Code: ErrorCodeScrape, Message: "conversion failed"}
	}
	if fromCurrency == toCurrency {
		return amount, toCurrency, nil
	}
	return s.amount, s.currency, nil
}
