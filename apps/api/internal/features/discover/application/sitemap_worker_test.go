package application

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
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
