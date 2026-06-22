package httpx

import (
	"time"

	tls_client "github.com/bogdanfinn/tls-client"
	"github.com/bogdanfinn/tls-client/profiles"
)

// ChromeProfile is the tls-client fingerprint profile used by the anti-bot
// static fetcher. Its major version MUST stay aligned with the httpfetch
// User-Agent pool (Chrome 124) so the User-Agent, sec-ch-ua client hints, the
// JA3/JA4 TLS fingerprint and the HTTP/2 fingerprint all agree on ONE Chrome
// version — a mismatch between layers is exactly what fingerprinting WAFs flag.
var ChromeProfile = profiles.Chrome_124

// NewChromeClient returns a tls-client HTTP client that presents a COMPLETE,
// consistent Chrome fingerprint: the JA3/JA4 TLS ClientHello AND the HTTP/2
// layer (SETTINGS frame values/order, WINDOW_UPDATE, header order, pseudo-header
// order, no PRIORITY frames). This is what distinguishes it from
// NewUTLSTransport, which spoofs only the TLS layer and pins HTTP/1.1 (a
// half-fake fingerprint: Chrome JA3 + non-Chrome HTTP/1.1) — that transport is
// retained for the discover sitemap worker, which fetches robots/sitemaps, not
// anti-bot-guarded product pages.
//
// Redirects are NOT followed here (WithNotFollowRedirects): the static fetcher
// does its own per-hop SSRF-checked redirect handling, so it must keep control.
// timeout bounds the whole request as a backstop to the per-request context
// deadline the caller also sets.
func NewChromeClient(timeout time.Duration) (tls_client.HttpClient, error) {
	jar := tls_client.NewCookieJar()
	options := []tls_client.HttpClientOption{
		tls_client.WithClientProfile(ChromeProfile),
		tls_client.WithCookieJar(jar),
		tls_client.WithNotFollowRedirects(),
		tls_client.WithTimeoutMilliseconds(int(timeout.Milliseconds())),
		// Disable the transport's own gzip handling: we send Accept-Encoding
		// manually (it is part of the Chrome header set) and decode the body
		// ourselves, so the caller controls decompression and its error/CRC
		// checks. Without this fhttp strips Content-Encoding while only
		// case-sensitively decoding it. Does not affect the JA3/HTTP-2 fingerprint.
		tls_client.WithTransportOptions(&tls_client.TransportOptions{DisableCompression: true}),
	}
	return tls_client.NewHttpClient(tls_client.NewNoopLogger(), options...)
}
