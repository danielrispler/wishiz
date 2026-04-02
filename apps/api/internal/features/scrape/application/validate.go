package application

import (
	"context"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strings"
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

	if parsedURL.Scheme != "http" && parsedURL.Scheme != "https" {
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

	if ip, err := netip.ParseAddr(host); err == nil {
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

func IsRedirectAllowed(ctx context.Context, resolver HostResolver, candidate *url.URL) error {
	if candidate == nil {
		return BadRequest("redirect target is invalid")
	}

	_, err := ValidateProductURL(ctx, resolver, candidate.String())
	return err
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
