package httpfetch

import (
	"bytes"
	"compress/gzip"
	"context"
	"net"
	"net/http"
	"net/http/httptest"
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

func TestFetchRetriesThenSucceeds(t *testing.T) {
	t.Parallel()

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

func TestRetryClassificationAndBackoff(t *testing.T) {
	t.Parallel()

	if !isRetryable(http.StatusTooManyRequests) || isRetryable(http.StatusNotFound) {
		t.Fatalf("unexpected retry classification")
	}
	if got := backoff(0, 10*time.Second); got != maxBackoff {
		t.Fatalf("expected Retry-After capped at maxBackoff, got %s", got)
	}
}
