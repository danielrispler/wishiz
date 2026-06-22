package httpfetch

import (
	"bytes"
	"compress/gzip"
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/andybalholm/brotli"
)

type allowResolver struct{}

func (allowResolver) LookupIPAddr(context.Context, string) ([]net.IPAddr, error) {
	return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}}, nil
}

func TestFetchDecodesGzip(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		var buf bytes.Buffer
		gz := gzip.NewWriter(&buf)
		_, _ = gz.Write([]byte("<html>gzipped body</html>"))
		_ = gz.Close()
		w.Header().Set("Content-Encoding", "gzip")
		_, _ = w.Write(buf.Bytes())
	}))
	defer server.Close()

	result, err := New(allowResolver{}).Fetch(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if result.HTML != "<html>gzipped body</html>" {
		t.Fatalf("expected decoded gzip body, got %q", result.HTML)
	}
}

func TestFetchDecodesGzipUppercaseEncoding(t *testing.T) {
	t.Parallel()

	// Content-Encoding tokens are case-insensitive; "GZIP" must still be decoded,
	// not fed to the parser as raw compressed bytes.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		var buf bytes.Buffer
		gz := gzip.NewWriter(&buf)
		_, _ = gz.Write([]byte("<html>uppercase gzip</html>"))
		_ = gz.Close()
		w.Header().Set("Content-Encoding", "GZIP")
		_, _ = w.Write(buf.Bytes())
	}))
	defer server.Close()

	result, err := New(allowResolver{}).Fetch(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if result.HTML != "<html>uppercase gzip</html>" {
		t.Fatalf("expected decoded body for GZIP encoding, got %q", result.HTML)
	}
}

func TestFetchTruncatedGzipErrors(t *testing.T) {
	t.Parallel()

	// A truncated gzip stream must surface as an error, not be silently accepted
	// as partial HTML.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		var buf bytes.Buffer
		gz := gzip.NewWriter(&buf)
		_, _ = gz.Write([]byte("<html>this body is long enough to be cut mid-stream</html>"))
		_ = gz.Close()
		raw := buf.Bytes()
		w.Header().Set("Content-Encoding", "gzip")
		w.Header().Set("Content-Length", strconv.Itoa(len(raw)/2))
		_, _ = w.Write(raw[:len(raw)/2]) // drop the second half (data + trailer)
	}))
	defer server.Close()

	if _, err := New(allowResolver{}).Fetch(context.Background(), server.URL); err == nil {
		t.Fatal("expected an error from a truncated gzip body, got nil")
	}
}

func TestFetchDecodesBrotli(t *testing.T) {
	t.Parallel()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		var buf bytes.Buffer
		bw := brotli.NewWriter(&buf)
		_, _ = bw.Write([]byte("<html>brotli body</html>"))
		_ = bw.Close()
		w.Header().Set("Content-Encoding", "br")
		_, _ = w.Write(buf.Bytes())
	}))
	defer server.Close()

	result, err := New(allowResolver{}).Fetch(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if result.HTML != "<html>brotli body</html>" {
		t.Fatalf("expected decoded brotli body, got %q", result.HTML)
	}
}

func TestClientRedirectTarget(t *testing.T) {
	t.Parallel()

	const final = "https://shop.example/p"
	cases := []struct {
		name string
		body string
		want string
	}{
		{
			name: "meta refresh relative",
			body: `<meta http-equiv="refresh" content="0; url=/final">`,
			want: "https://shop.example/final",
		},
		{
			name: "meta refresh absolute",
			body: `<meta http-equiv="refresh" content="5;URL=https://shop.example/dest">`,
			want: "https://shop.example/dest",
		},
		{
			name: "window.location.href",
			body: `<script>window.location.href = "/go";</script>`,
			want: "https://shop.example/go",
		},
		{
			name: "location.replace",
			body: `<script>location.replace("https://shop.example/r")</script>`,
			want: "https://shop.example/r",
		},
		{name: "no redirect", body: `<html><body>nothing</body></html>`, want: ""},
		{name: "same url is not a redirect", body: `<meta http-equiv="refresh" content="0; url=/p">`, want: ""},
		{
			name: "non-http scheme ignored",
			body: `<script>window.location.href = "javascript:void(0)";</script>`,
			want: "",
		},
	}
	for _, tc := range cases {
		if got := clientRedirectTarget(tc.body, final); got != tc.want {
			t.Errorf("%s: clientRedirectTarget = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestFetchDoesNotFollowDisallowedRedirect(t *testing.T) {
	t.Parallel()

	// The redirect hop is re-validated through the SSRF guard. A meta-refresh to a
	// loopback target (the test server itself) is blocked, so Fetch returns the
	// original document rather than following the unsafe hop or erroring.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/final" {
			_, _ = w.Write([]byte("<html>should not be reached</html>"))
			return
		}
		_, _ = w.Write([]byte(
			`<html><head><meta http-equiv="refresh" content="0; url=/final"></head><body></body></html>`))
	}))
	defer server.Close()

	result, err := New(allowResolver{}).Fetch(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if strings.Contains(result.HTML, "should not be reached") {
		t.Fatalf("must not follow a redirect that fails the SSRF guard")
	}
	if !strings.Contains(result.HTML, "http-equiv") {
		t.Fatalf("expected the original document, got %q", result.HTML)
	}
}

func TestFetchSendsBrowserHeaders(t *testing.T) {
	t.Parallel()

	var got http.Header
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r.Header.Clone()
		_, _ = w.Write([]byte("<html>ok</html>"))
	}))
	defer server.Close()

	if _, err := New(allowResolver{}).Fetch(context.Background(), server.URL); err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if !strings.Contains(got.Get("User-Agent"), "Chrome") {
		t.Fatalf("expected Chrome UA, got %q", got.Get("User-Agent"))
	}
	if got.Get("sec-ch-ua") == "" || got.Get("Sec-Fetch-Mode") != "navigate" {
		t.Fatalf("expected client-hint headers, got sec-ch-ua=%q sec-fetch-mode=%q",
			got.Get("sec-ch-ua"), got.Get("Sec-Fetch-Mode"))
	}
}

// TestFetchRetriesThenSucceeds is serial on purpose: it mutates the package-global
// backoffBase, which the parallel TestRetryClassificationAndBackoff reads via
// backoff(). Keeping it in the serial phase avoids a data race on that global.
//
//nolint:paralleltest // intentionally serial (mutates backoffBase); see comment above.
func TestFetchRetriesThenSucceeds(t *testing.T) {
	old := backoffBase
	backoffBase = time.Millisecond
	defer func() { backoffBase = old }()

	var calls int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		if calls == 1 {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		_, _ = w.Write([]byte("<html>recovered</html>"))
	}))
	defer server.Close()

	result, err := New(allowResolver{}).Fetch(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if result.HTML != "<html>recovered</html>" || calls != 2 {
		t.Fatalf("expected retry to succeed on 2nd call, got html=%q calls=%d", result.HTML, calls)
	}
}

func TestFetchFollowsHTTPRedirectCarryingCookies(t *testing.T) {
	t.Parallel()

	// An HTTP 3xx with a relative Location is followed; a cookie set on hop 1 must
	// be sent on hop 2 (the per-Fetch tls-client jar is reused across hops).
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/":
			http.SetCookie(w, &http.Cookie{Name: "sid", Value: "abc"})
			http.Redirect(w, r, "/step2", http.StatusFound) // relative Location
		case "/step2":
			if cookie, err := r.Cookie("sid"); err == nil && cookie.Value == "abc" {
				_, _ = w.Write([]byte("<html>cookie-carried</html>"))
				return
			}
			_, _ = w.Write([]byte("<html>cookie-missing</html>"))
		}
	}))
	defer server.Close()

	client := New(allowResolver{})
	client.validateHop = func(context.Context, string) error { return nil } // allow the loopback hop
	result, err := client.Fetch(context.Background(), server.URL)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if !strings.Contains(result.HTML, "cookie-carried") {
		t.Fatalf("expected cookie carried across the redirect, got %q", result.HTML)
	}
	if !strings.HasSuffix(result.FinalURL, "/step2") {
		t.Fatalf("expected final URL at /step2 (relative Location resolved), got %q", result.FinalURL)
	}
}

func TestFetchHTTPRedirectLoopHitsCap(t *testing.T) {
	t.Parallel()

	// An unbounded HTTP 3xx loop must stop at the hop cap and error, not spin.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/next", http.StatusFound)
	}))
	defer server.Close()

	client := New(allowResolver{})
	client.validateHop = func(context.Context, string) error { return nil }
	if _, err := client.Fetch(context.Background(), server.URL); err == nil {
		t.Fatal("expected an error from an unbounded redirect loop")
	}
}

func TestFetchRejectsHTTPRedirectToPrivateHost(t *testing.T) {
	t.Parallel()

	// With the real SSRF guard, an HTTP 3xx Location pointing at the loopback
	// server (a private host) must be rejected mid-chain as a hard error.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/private", http.StatusFound)
	}))
	defer server.Close()

	if _, err := New(allowResolver{}).Fetch(context.Background(), server.URL); err == nil {
		t.Fatal("expected the SSRF guard to reject the HTTP redirect to a private host")
	}
}

func TestFetchHonorsContextDeadlineOnSlowServer(t *testing.T) {
	t.Parallel()

	// A hung server must not exceed the request deadline: Fetch returns promptly
	// with an error when the context deadline trips.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-r.Context().Done():
		case <-time.After(3 * time.Second):
			_, _ = w.Write([]byte("<html>too slow</html>"))
		}
	}))
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	start := time.Now()
	_, err := New(allowResolver{}).Fetch(ctx, server.URL)
	elapsed := time.Since(start)
	if err == nil {
		t.Fatal("expected a deadline error from a slow server")
	}
	if elapsed > 2*time.Second {
		t.Fatalf("expected Fetch to return near the 200ms deadline, took %s", elapsed)
	}
}

func TestRetryClassificationAndBackoff(t *testing.T) {
	t.Parallel()

	if !isRetryable(http.StatusTooManyRequests) || isRetryable(http.StatusNotFound) {
		t.Fatalf("unexpected retry classification")
	}
	if got := backoff(0, 10*time.Second); got != maxBackoff {
		t.Fatalf("expected Retry-After capped at maxBackoff, got %s", got)
	}
}
