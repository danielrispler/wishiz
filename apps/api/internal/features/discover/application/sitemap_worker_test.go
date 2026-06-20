package application

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"sync/atomic"
	"testing"
	"time"
)

func TestSitemapURLSetLocsIncludesURLsAndNestedSitemaps(t *testing.T) {
	t.Parallel()

	parsed := sitemapURLSet{
		URLs: []sitemapEntry{
			{Loc: "https://example.com/product-a"},
			{Loc: ""},
		},
		Sitemaps: []sitemapEntry{
			{Loc: "https://example.com/sitemap-1.xml"},
			{Loc: "https://example.com/sitemap-2.xml"},
		},
	}

	got := parsed.locs()
	want := []string{
		"https://example.com/product-a",
		"https://example.com/sitemap-1.xml",
		"https://example.com/sitemap-2.xml",
	}
	if !slices.Equal(got, want) {
		t.Fatalf("expected locs %v, got %v", want, got)
	}
}

func TestCollectSitemapURLsTraversesNestedSitemaps(t *testing.T) {
	t.Parallel()

	mux := http.NewServeMux()
	mux.HandleFunc("/root.xml", func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, `
			<sitemapindex>
				<sitemap><loc>`+serverURL(r)+`/child-a.xml</loc></sitemap>
				<sitemap><loc>`+serverURL(r)+`/child-b.xml</loc></sitemap>
			</sitemapindex>
		`)
	})
	mux.HandleFunc("/child-a.xml", func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, `
			<urlset>
				<url><loc>`+serverURL(r)+`/products/a</loc></url>
			</urlset>
		`)
	})
	mux.HandleFunc("/child-b.xml", func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, `
			<urlset>
				<url><loc>`+serverURL(r)+`/products/b</loc></url>
			</urlset>
		`)
	})

	server := httptest.NewServer(mux)
	defer server.Close()

	worker := &SitemapWorker{
		logger:     slog.New(slog.NewTextHandler(io.Discard, nil)),
		httpClient: server.Client(),
	}

	got, err := worker.collectSitemapURLs(context.Background(), server.URL+"/root.xml", 0)
	if err != nil {
		t.Fatalf("collect sitemap urls: %v", err)
	}

	want := []string{
		server.URL + "/products/a",
		server.URL + "/products/b",
	}
	slices.Sort(got)
	slices.Sort(want)
	if !slices.Equal(got, want) {
		t.Fatalf("expected urls %v, got %v", want, got)
	}
}

func TestCollectSitemapURLsLimitsNestedFetchConcurrency(t *testing.T) {
	t.Parallel()

	var inFlight atomic.Int32
	var peak atomic.Int32

	mux := http.NewServeMux()
	mux.HandleFunc("/root.xml", func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.WriteString(w, `
			<sitemapindex>
				<sitemap><loc>`+serverURL(r)+`/child-1.xml</loc></sitemap>
				<sitemap><loc>`+serverURL(r)+`/child-2.xml</loc></sitemap>
				<sitemap><loc>`+serverURL(r)+`/child-3.xml</loc></sitemap>
				<sitemap><loc>`+serverURL(r)+`/child-4.xml</loc></sitemap>
				<sitemap><loc>`+serverURL(r)+`/child-5.xml</loc></sitemap>
			</sitemapindex>
		`)
	})
	for i := 1; i <= 5; i++ {
		path := "/child-" + string(rune('0'+i)) + ".xml"
		productPath := "/products/" + string(rune('0'+i))
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			current := inFlight.Add(1)
			for {
				prev := peak.Load()
				if current <= prev || peak.CompareAndSwap(prev, current) {
					break
				}
			}
			time.Sleep(50 * time.Millisecond)
			inFlight.Add(-1)
			_, _ = io.WriteString(w, `<urlset><url><loc>`+serverURL(r)+productPath+`</loc></url></urlset>`)
		})
	}

	server := httptest.NewServer(mux)
	defer server.Close()

	worker := &SitemapWorker{
		logger:     slog.New(slog.NewTextHandler(io.Discard, nil)),
		httpClient: server.Client(),
	}

	got, err := worker.collectSitemapURLs(context.Background(), server.URL+"/root.xml", 0)
	if err != nil {
		t.Fatalf("collect sitemap urls: %v", err)
	}

	if len(got) != 5 {
		t.Fatalf("expected 5 urls, got %d", len(got))
	}
	if peak.Load() > maxConcurrentSitemapFetches {
		t.Fatalf("expected peak concurrency <= %d, got %d", maxConcurrentSitemapFetches, peak.Load())
	}
}

func serverURL(r *http.Request) string {
	return "http://" + r.Host
}

// validDiscoverCategories mirrors the discover_products category CHECK constraint
// in 000001_init_wishlists.up.sql. The worker may only emit these.
var validDiscoverCategories = map[string]struct{}{
	"fashion":     {},
	"beauty":      {},
	"home":        {},
	"accessories": {},
	"gifts":       {},
	"travel":      {},
}

func TestDefaultSitemapBrandsAreValid(t *testing.T) {
	t.Parallel()

	brands := defaultSitemapBrands()
	if len(brands) == 0 {
		t.Fatal("expected at least one sitemap brand")
	}

	seenNames := make(map[string]struct{}, len(brands))
	seenURLs := make(map[string]struct{}, len(brands))

	for _, b := range brands {
		if b.Name == "" {
			t.Fatalf("brand with empty name: %+v", b)
		}
		if _, dup := seenNames[b.Name]; dup {
			t.Fatalf("duplicate brand name %q", b.Name)
		}
		seenNames[b.Name] = struct{}{}

		if _, dup := seenURLs[b.SitemapURL]; dup {
			t.Fatalf("duplicate sitemap url %q (brand %q)", b.SitemapURL, b.Name)
		}
		seenURLs[b.SitemapURL] = struct{}{}

		if _, ok := validDiscoverCategories[b.Category]; !ok {
			t.Fatalf("brand %q has invalid category %q", b.Name, b.Category)
		}

		u, err := url.Parse(b.SitemapURL)
		if err != nil {
			t.Fatalf("brand %q sitemap url %q does not parse: %v", b.Name, b.SitemapURL, err)
		}
		if u.Scheme != "https" && u.Scheme != "http" {
			t.Fatalf("brand %q sitemap url %q has non-http(s) scheme %q", b.Name, b.SitemapURL, u.Scheme)
		}
		if u.Hostname() == "" {
			t.Fatalf("brand %q sitemap url %q has empty host", b.Name, b.SitemapURL)
		}
	}
}

func TestDefaultSitemapBrandsCategoryAssignment(t *testing.T) {
	t.Parallel()

	byName := make(map[string]sitemapBrand)
	for _, b := range defaultSitemapBrands() {
		byName[b.Name] = b
	}

	want := map[string]string{
		"Diptyque":       "beauty",
		"Le Labo":        "beauty",
		"Aesop":          "beauty",
		"West Elm":       "home",
		"Crate & Barrel": "home",
		"Pottery Barn":   "home",
		"Zara":           "fashion",
	}
	for name, category := range want {
		b, ok := byName[name]
		if !ok {
			t.Fatalf("expected brand %q in sitemap list", name)
		}
		if b.Category != category {
			t.Fatalf("brand %q: expected category %q, got %q", name, category, b.Category)
		}
	}
}
