package httpx

import (
	"net/http"
	"testing"
	"time"
)

func TestNewServerSetsReadTimeout(t *testing.T) {
	t.Parallel()

	server := NewServer(":8080", http.NewServeMux())

	if server.ReadTimeout != 15*time.Second {
		t.Fatalf("expected read timeout of 15s, got %s", server.ReadTimeout)
	}
	if server.ReadHeaderTimeout != 5*time.Second {
		t.Fatalf("expected read header timeout of 5s, got %s", server.ReadHeaderTimeout)
	}
}
