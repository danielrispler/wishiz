// Package httpx holds shared low-level HTTP transport helpers.
package httpx

import (
	"context"
	"net"
	"net/http"
	"time"

	utls "github.com/refraction-networking/utls"
)

// NewUTLSTransport returns an http.Transport that dials TLS with a Chrome
// fingerprint (utls) to dodge naive TLS-fingerprint blocks, pinned to HTTP/1.1
// for goquery-friendly responses. dialTimeout bounds the TCP dial. This is the
// single source of truth shared by the static fetcher and the discover sitemap
// worker (both need the same Chrome-TLS handshake).
func NewUTLSTransport(dialTimeout time.Duration) *http.Transport {
	return &http.Transport{
		ForceAttemptHTTP2: false,
		DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			conn, err := (&net.Dialer{Timeout: dialTimeout}).DialContext(ctx, network, addr)
			if err != nil {
				return nil, err
			}
			host, _, _ := net.SplitHostPort(addr)
			uConn := utls.UClient(conn, &utls.Config{ServerName: host}, utls.HelloChrome_Auto)
			if err := uConn.BuildHandshakeState(); err != nil {
				conn.Close()
				return nil, err
			}
			// Strip "h2" from ALPN to force HTTP/1.1 and prevent the framing mismatch.
			for _, ext := range uConn.Extensions {
				if alpn, ok := ext.(*utls.ALPNExtension); ok {
					alpn.AlpnProtocols = []string{"http/1.1"}
					break
				}
			}
			if err := uConn.HandshakeContext(ctx); err != nil {
				conn.Close()
				return nil, err
			}
			return uConn, nil
		},
	}
}
