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

type stubResolver struct {
	addresses []net.IPAddr
}

func (s stubResolver) LookupIPAddr(ctx context.Context, host string) ([]net.IPAddr, error) {
	if len(s.addresses) == 0 {
		return []net.IPAddr{{IP: net.ParseIP("93.184.216.34")}}, nil
	}
	return s.addresses, nil
}
