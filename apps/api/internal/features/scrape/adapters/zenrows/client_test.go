package zenrows

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// serverClient spins up an httptest server and returns a Client pointed at it.
func serverClient(t *testing.T, handler http.HandlerFunc) *Client {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	client := New("test-key", slog.New(slog.NewTextHandler(io.Discard, nil)))
	client.baseURL = server.URL + "/"
	return client
}

func TestFetchSuccess(t *testing.T) {
	t.Parallel()
	var gotQuery url.Values
	client := serverClient(t, func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.Query()
		w.Header().Set("Zr-Final-Url", "https://shop.example/final")
		w.Header().Set("X-Request-Cost", "25")
		_, _ = io.WriteString(w, "<html>rendered</html>")
	})

	result, err := client.Fetch(context.Background(), "https://shop.example/p", "gb")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.HTML != "<html>rendered</html>" {
		t.Fatalf("HTML = %q", result.HTML)
	}
	if result.FinalURL != "https://shop.example/final" {
		t.Fatalf("FinalURL = %q, want the Zr-Final-Url header", result.FinalURL)
	}
	if got := gotQuery.Get("apikey"); got != "test-key" {
		t.Errorf("apikey = %q", got)
	}
	if got := gotQuery.Get("url"); got != "https://shop.example/p" {
		t.Errorf("url = %q", got)
	}
	if got := gotQuery.Get("js_render"); got != "true" {
		t.Errorf("js_render = %q, want true", got)
	}
	if got := gotQuery.Get("premium_proxy"); got != "true" {
		t.Errorf("premium_proxy = %q, want true", got)
	}
	if got := gotQuery.Get("proxy_country"); got != "gb" {
		t.Errorf("proxy_country = %q, want gb", got)
	}
}

func TestFetchOmitsProxyCountryWhenEmpty(t *testing.T) {
	t.Parallel()
	var gotQuery url.Values
	client := serverClient(t, func(w http.ResponseWriter, r *http.Request) {
		gotQuery = r.URL.Query()
		_, _ = io.WriteString(w, "<html>ok</html>")
	})

	if _, err := client.Fetch(context.Background(), "https://shop.example/p", ""); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if gotQuery.Has("proxy_country") {
		t.Fatalf("proxy_country should be omitted when empty, got %q", gotQuery.Get("proxy_country"))
	}
}

func TestFetchFinalURLFallsBackToRawURL(t *testing.T) {
	t.Parallel()
	client := serverClient(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "<html>ok</html>") // no Zr-Final-Url header
	})

	result, err := client.Fetch(context.Background(), "https://shop.example/p", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.FinalURL != "https://shop.example/p" {
		t.Fatalf("FinalURL = %q, want the raw URL fallback", result.FinalURL)
	}
}

func TestFetchNon200IsError(t *testing.T) {
	t.Parallel()
	client := serverClient(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusPaymentRequired) // 402: no credits
	})

	_, err := client.Fetch(context.Background(), "https://shop.example/p", "")
	if err == nil {
		t.Fatal("expected an error for a non-200 status")
	}
	if want := "zenrows status 402"; !strings.Contains(err.Error(), want) {
		t.Fatalf("error = %q, want it to mention %q", err.Error(), want)
	}
}

func TestFetchContextCanceledIsError(t *testing.T) {
	t.Parallel()
	client := serverClient(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, "<html>ok</html>")
	})

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := client.Fetch(ctx, "https://shop.example/p", ""); err == nil {
		t.Fatal("expected an error for a canceled context")
	}
}
