package httpfetch

import "sync/atomic"

// browserProfile is a self-consistent set of Client Hints headers: the UA string
// and its matching sec-ch-ua / platform must agree or anti-bot heuristics flag
// the mismatch.
type browserProfile struct {
	userAgent       string
	secCHUA         string
	secCHUAMobile   string
	secCHUAPlatform string
}

// desktopProfiles is a rotation pool of desktop Chrome profiles. Every profile's
// major version MUST match httpx.ChromeProfile (Chrome 124) so the UA, sec-ch-ua,
// JA3/JA4 and HTTP/2 fingerprint all agree on one Chrome version — a cross-layer
// version mismatch is exactly what fingerprinting WAFs flag.
var desktopProfiles = []browserProfile{
	{
		userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
			"(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
		secCHUA:         `"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"`,
		secCHUAMobile:   "?0",
		secCHUAPlatform: `"Windows"`,
	},
	{
		userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
			"(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
		secCHUA:         `"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"`,
		secCHUAMobile:   "?0",
		secCHUAPlatform: `"macOS"`,
	},
	{
		userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
			"(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
		secCHUA:         `"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"`,
		secCHUAMobile:   "?0",
		secCHUAPlatform: `"Linux"`,
	},
}

var profileCounter atomic.Uint64

// nextProfile round-robins through the pool so repeated requests don't all share
// one fingerprint.
func nextProfile() browserProfile {
	index := profileCounter.Add(1) - 1
	return desktopProfiles[index%uint64(len(desktopProfiles))]
}

// RandomUserAgent returns a realistic Chrome UA from the rotation pool. It lets
// other adapters (e.g. the Shopify probe) reuse this pool instead of sending a
// self-identifying bot UA that UA-blocking stores 403.
func RandomUserAgent() string {
	return nextProfile().userAgent
}
