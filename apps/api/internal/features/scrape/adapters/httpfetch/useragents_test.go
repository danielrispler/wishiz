package httpfetch

import (
	"strings"
	"testing"
)

// TestRandomUserAgent confirms the exported accessor returns a realistic Chrome
// UA from the rotation pool (so callers like the Shopify probe stop sending a
// self-identifying WishizBot UA).
func TestRandomUserAgent(t *testing.T) {
	t.Parallel()

	pool := map[string]bool{}
	for _, p := range desktopProfiles {
		pool[p.userAgent] = true
	}
	for i := 0; i < len(desktopProfiles)*2; i++ {
		ua := RandomUserAgent()
		if !strings.Contains(ua, "Mozilla/5.0") {
			t.Fatalf("RandomUserAgent()=%q, expected a realistic browser UA", ua)
		}
		if !pool[ua] {
			t.Fatalf("RandomUserAgent()=%q not from the rotation pool", ua)
		}
	}
}
