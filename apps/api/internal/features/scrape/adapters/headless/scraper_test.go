package headless

import (
	"context"
	"net"
	"testing"
)

func TestValidateRequestedURLRejectsPrivateTargets(t *testing.T) {
	t.Parallel()

	scraper := &Scraper{
		resolver: resolverStub{
			addresses: []net.IPAddr{{IP: net.ParseIP("127.0.0.1")}},
		},
	}

	if err := scraper.validateRequestedURL(context.Background(), "https://example.com/redirect"); err == nil {
		t.Fatalf("expected private target to be rejected")
	}
}

func TestValidateRequestedURLAllowsPublicTargets(t *testing.T) {
	t.Parallel()

	scraper := &Scraper{
		resolver: resolverStub{
			addresses: []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}},
		},
	}

	if err := scraper.validateRequestedURL(context.Background(), "https://example.com/product"); err != nil {
		t.Fatalf("expected public target to be allowed, got %v", err)
	}
}

type resolverStub struct {
	addresses []net.IPAddr
}

func (s resolverStub) LookupIPAddr(_ context.Context, _ string) ([]net.IPAddr, error) {
	return s.addresses, nil
}
