package application

import (
	"context"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strings"
)

const (
	schemeHTTP  = "http"
	schemeHTTPS = "https"
)

type HostResolver interface {
	LookupIPAddr(ctx context.Context, host string) ([]net.IPAddr, error)
}

func ValidateProductURL(ctx context.Context, resolver HostResolver, rawURL string) (*url.URL, error) {
	trimmed := strings.TrimSpace(rawURL)
	if trimmed == "" {
		return nil, BadRequest("url is required")
	}

	parsedURL, err := url.Parse(trimmed)
	if err != nil {
		return nil, BadRequest("url must be a valid http or https URL")
	}

	if parsedURL.Scheme != schemeHTTP && parsedURL.Scheme != schemeHTTPS {
		return nil, BadRequest("url must use http or https")
	}
	if parsedURL.Host == "" {
		return nil, BadRequest("url must include a host")
	}

	host := parsedURL.Hostname()
	if host == "" {
		return nil, BadRequest("url must include a host")
	}
	if isDisallowedHost(host) {
		return nil, BadRequest("url host is not allowed")
	}

	if ip, parseErr := netip.ParseAddr(host); parseErr == nil {
		if isDisallowedAddr(ip) {
			return nil, BadRequest("url host is not allowed")
		}
		return parsedURL, nil
	}

	if resolver == nil {
		return parsedURL, nil
	}

	addresses, err := resolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, ScrapeFailed(fmt.Sprintf("could not resolve host %q", host))
	}

	for _, address := range addresses {
		addr, ok := netip.AddrFromSlice(address.IP)
		if !ok {
			continue
		}
		if isDisallowedAddr(addr) {
			return nil, BadRequest("url host is not allowed")
		}
	}

	return parsedURL, nil
}

func IsRedirectAllowed(ctx context.Context, resolver HostResolver, candidate string) error {
	if strings.TrimSpace(candidate) == "" {
		return BadRequest("redirect target is invalid")
	}

	_, err := ValidateProductURL(ctx, resolver, candidate)
	return err
}

// IsBrowserSubresourceAllowed gates a request the headless browser is about to
// make. Real pages routinely fetch non-http schemes (data:, blob:, about:,
// chrome-extension:, ws/wss, filesystem:) that either cannot reach internal
// hosts or cannot return their body into the rendered DOM we extract; those are
// always allowed so a benign sub-resource never aborts the whole render. Only
// http/https — the SSRF surface whose response can be injected into the page —
// is run through the policy, so a fetch/redirect to a private address is still
// blocked.
func IsBrowserSubresourceAllowed(ctx context.Context, resolver HostResolver, candidate string) error {
	parsed, _ := url.Parse(strings.TrimSpace(candidate))
	if parsed == nil {
		return nil // unparseable target — not an http(s) host we can or need to SSRF-check
	}
	switch strings.ToLower(parsed.Scheme) {
	case schemeHTTP, schemeHTTPS:
		return IsRedirectAllowed(ctx, resolver, candidate)
	default:
		return nil
	}
}

func isDisallowedHost(host string) bool {
	normalized := strings.ToLower(strings.TrimSpace(host))
	switch normalized {
	case "", "localhost", "localhost.localdomain":
		return true
	default:
		return false
	}
}

func isDisallowedAddr(addr netip.Addr) bool {
	return addr.IsLoopback() ||
		addr.IsPrivate() ||
		addr.IsLinkLocalUnicast() ||
		addr.IsLinkLocalMulticast() ||
		addr.IsMulticast() ||
		addr.IsUnspecified()
}
