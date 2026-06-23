package application

import "strings"

// proxyCountryByTLD maps a ccTLD to the ISO 3166-1 alpha-2 country used as the
// ZenRows residential-proxy exit. Pinning the exit to the site's country keeps
// the backstop's localized currency consistent with the own pipeline's locale/TLD
// inference, so the second pass reinforces rather than conflicts (fewer wasted
// 25× fetches). Generic TLDs (.com/.net/.org) and multi-country .eu are absent on
// purpose: there is no single correct exit, so the fetch is left unpinned and the
// verdict-floor guard in ScrapeImport absorbs any geo conflict. The ccTLD equals
// the country code except .uk → gb.
var proxyCountryByTLD = map[string]string{
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
