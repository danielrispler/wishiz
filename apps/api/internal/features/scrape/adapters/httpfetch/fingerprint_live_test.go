//go:build scrapelive

// This live test is the actual proof that the static fetcher presents a COMPLETE
// Chrome fingerprint (JA3/JA4 + HTTP/2), not the old half-fake (Chrome TLS +
// HTTP/1.1). It hits tls.peet.ws/api/all, which echoes back the JA3/JA4 and the
// Akamai HTTP/2 fingerprint it observed. Gated behind `scrapelive` because it
// needs outbound network.
//
//	go test -tags scrapelive -run Fingerprint -v ./internal/features/scrape/adapters/httpfetch/
//
// Hard assertions (correct-by-construction, not brittle hashes): the connection
// negotiated HTTP/2 (the old transport pinned HTTP/1.1, so this alone proves the
// new layer), the Akamai fingerprint carries Chrome's pseudo-header order
// (m,a,s,p), and the JA4 is a TLS 1.3 ClientHello (t13d…). The full echoed JSON
// is logged so the JA3/JA4/Akamai values can be eyeballed against a known Chrome.
package httpfetch

import (
	"context"
	"encoding/json"
	"net"
	"strings"
	"testing"
	"time"
)

func TestFingerprintIsChromeNotGo(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	result, err := New(net.DefaultResolver).Fetch(ctx, "https://tls.peet.ws/api/all")
	if err != nil {
		// Endpoint/network unavailable is an external limitation, not a
		// regression — skip rather than fail (matches the eval live-test stance).
		t.Skipf("could not reach tls.peet.ws (%v) — run with network to prove the fingerprint", err)
	}
	t.Logf("tls.peet.ws/api/all echoed:\n%s", result.HTML)

	var echoed struct {
		HTTPVersion string `json:"http_version"`
		UserAgent   string `json:"user_agent"`
		TLS         struct {
			JA3     string `json:"ja3"`
			JA3Hash string `json:"ja3_hash"`
			JA4     string `json:"ja4"`
		} `json:"tls"`
		HTTP2 struct {
			AkamaiFingerprint string `json:"akamai_fingerprint"`
		} `json:"http2"`
	}
	if err := json.Unmarshal([]byte(result.HTML), &echoed); err != nil {
		t.Fatalf("parse peet.ws response: %v", err)
	}

	if echoed.HTTPVersion != "h2" {
		t.Fatalf("expected HTTP/2 (h2), got %q — the HTTP/2 fingerprint layer is not active", echoed.HTTPVersion)
	}
	// Chrome's HTTP/2 pseudo-header order is :method,:authority,:scheme,:path =
	// m,a,s,p (the last segment of the Akamai fingerprint). This is what we set
	// via PHeaderOrderKey; a default Go client would not present it the same way.
	if !strings.Contains(echoed.HTTP2.AkamaiFingerprint, "m,a,s,p") {
		t.Fatalf("Akamai HTTP/2 fingerprint is not Chrome-shaped (missing m,a,s,p pseudo-order): %q",
			echoed.HTTP2.AkamaiFingerprint)
	}
	if !strings.HasPrefix(echoed.TLS.JA4, "t13d") {
		t.Fatalf("JA4 is not a Chrome TLS 1.3 ClientHello (t13d…): %q", echoed.TLS.JA4)
	}
	if !strings.Contains(echoed.UserAgent, "Chrome/124") {
		t.Fatalf("echoed User-Agent is not aligned to the Chrome 124 pool: %q", echoed.UserAgent)
	}
}
