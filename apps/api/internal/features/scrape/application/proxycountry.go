package application

import "strings"

// proxyCountryByTLD maps a ccTLD to the ISO 3166-1 alpha-2 country used as the
// ZenRows residential-proxy exit. Pinning the exit to the site's country keeps
// the backstop's localized currency consistent with the own pipeline's locale/TLD
// inference, so the second pass reinforces rather than conflicts (fewer wasted
// 25× fetches). The generic gTLDs (.com/.net/.org) pin to "us": ZenRows otherwise
// routes them through a random residential exit, and a slow/contested exit to a US
// retailer (wayfair.com) stalls the render past ZENROWS_TIMEOUT — the main cause of
// total-fails. US is the safest single commerce exit (USD, full content), and the
// verdict-floor guard plus explicit-only currency assignment keep a wrong-locale
// price from ever auto-completing. Multi-country .eu stays unpinned (no single
// correct exit). The ccTLD equals the country code except .uk → gb.
var proxyCountryByTLD = map[string]string{
	"com": "us", "net": "us", "org": "us",
	"il": "il", "uk": "gb",
	"de": "de", "fr": "fr", "es": "es", "it": "it", "nl": "nl", "ie": "ie",
	"ca": "ca", "au": "au", "jp": "jp", "ch": "ch",
	"se": "se", "no": "no", "dk": "dk", "pl": "pl", "cz": "cz",
}

// inferProxyCountry returns the residential-proxy exit country for host, derived
// from its ccTLD, or "" when the TLD is generic/unknown (leave the exit unpinned).
func inferProxyCountry(host string) string {
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	index := strings.LastIndex(host, ".")
	if index < 0 {
		return ""
	}
	return proxyCountryByTLD[host[index+1:]]
}
