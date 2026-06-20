package application

import (
	"context"
	"net"
	"testing"
)

func TestValidateProductURLRejectsResolvedPrivateAddress(t *testing.T) {
	t.Parallel()

	_, err := ValidateProductURL(context.Background(), stubResolver{
		addresses: []net.IPAddr{
			{IP: net.ParseIP("10.0.0.8")},
		},
	}, "https://example.com/product")
	if err == nil {
		t.Fatalf("expected validation error")
	}
}

// IsBrowserSubresourceAllowed must NOT abort the headless render on benign
// non-network schemes (data:/blob:/about:) that real pages routinely request,
// while still enforcing the SSRF policy on actual http/https/ws(s) fetches.
func TestIsBrowserSubresourceAllowed(t *testing.T) {
	t.Parallel()

	allowed := []string{
		"data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==",
		"blob:https://www.aritzia.com/3f2504e0-4f89-11d3-9a0c-0305e82c3301",
		"about:blank",
		"chrome-extension://abc/inject.js",
		"",
		"https://www.aritzia.com/us/en/product/x.html",
		"http://cdn.example.com/app.js",
	}
	for _, raw := range allowed {
		if err := IsBrowserSubresourceAllowed(context.Background(), stubResolver{}, raw); err != nil {
			t.Errorf("scheme %q should be allowed, got %v", raw, err)
		}
	}

	blocked := []string{
		"http://127.0.0.1:8080/admin",
		"https://localhost/secret",
		"http://169.254.169.254/latest/meta-data",
	}
	for _, raw := range blocked {
		if err := IsBrowserSubresourceAllowed(context.Background(), stubResolver{}, raw); err == nil {
			t.Errorf("SSRF target %q should be blocked", raw)
		}
	}

	// http/https to a host that resolves to a private address is still blocked.
	privateResolver := stubResolver{addresses: []net.IPAddr{{IP: net.ParseIP("10.0.0.8")}}}
	if err := IsBrowserSubresourceAllowed(context.Background(), privateResolver, "https://internal.example.com/x"); err == nil {
		t.Errorf("http(s) to private-resolved host should be blocked")
	}
}

type stubResolver struct {
	addresses []net.IPAddr
}

func (s stubResolver) LookupIPAddr(_ context.Context, _ string) ([]net.IPAddr, error) {
	if len(s.addresses) == 0 {
		return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}}, nil
	}
	return s.addresses, nil
}
