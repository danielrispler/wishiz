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

// A bare domain must never pass as a product name. The classic leak is an
// anti-bot / error page whose <title> is just the site host ("www.aritzia.com"):
// it slipped through because isDomainOnly stripped "www." from the host but not
// from the candidate, so "www.aritzia.com" != "aritzia.com" and survived.
func TestValidateNameRejectsBareDomain(t *testing.T) {
	t.Parallel()

	host := "www.aritzia.com"
	rejected := []string{
		"www.aritzia.com",
		"https://www.aritzia.com",
		"http://www.aritzia.com/",
		"www.aritzia.com/us/en/",
		"aritzia.com",
		"  WWW.ARITZIA.COM  ",
	}
	for _, name := range rejected {
		if ValidateName(name, host) {
			t.Errorf("expected %q to be rejected as a bare-domain name", name)
		}
	}

	accepted := []string{
		"The Lodge Pant™ - CruiseLinen™",
		"Aritzia Super Puff",  // brand word in a real product name is fine
		"Norre Media Console", // unrelated real name
	}
	for _, name := range accepted {
		if !ValidateName(name, host) {
			t.Errorf("expected %q to be accepted as a real product name", name)
		}
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
