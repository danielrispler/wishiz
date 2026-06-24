package legalhttp

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const sampleSupportEmail = "danielrispler@gmail.com"

func TestLegalRoutesRenderHTMLPages(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name        string
		path        string
		wantSnippet []string
	}{
		{
			name:        "privacy policy page",
			path:        "/privacy",
			wantSnippet: []string{"Privacy Policy", "Wishiz", sampleSupportEmail},
		},
		{
			name:        "support page",
			path:        "/support",
			wantSnippet: []string{"Support", sampleSupportEmail, "mailto:" + sampleSupportEmail},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			mux := http.NewServeMux()
			RegisterRoutes(mux, Options{SupportEmail: sampleSupportEmail})

			request := httptest.NewRequest(http.MethodGet, tc.path, http.NoBody)
			recorder := httptest.NewRecorder()
			mux.ServeHTTP(recorder, request)

			if recorder.Code != http.StatusOK {
				t.Fatalf("expected 200 for %s, got %d", tc.path, recorder.Code)
			}

			contentType := recorder.Header().Get("Content-Type")
			if !strings.Contains(contentType, "text/html") {
				t.Fatalf("expected text/html content type for %s, got %q", tc.path, contentType)
			}

			body := recorder.Body.String()
			for _, snippet := range tc.wantSnippet {
				if !strings.Contains(body, snippet) {
					t.Fatalf("expected %s body to contain %q, got %s", tc.path, snippet, body)
				}
			}
		})
	}
}
