package application

import (
	"net/url"
	"strconv"
	"strings"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// DefaultMaxPrice is the upper sanity bound on a scraped price amount.
const DefaultMaxPrice = 1e7

// antiBotNamePhrases are challenge/error page titles that must never be accepted
// as a product name (they are the classic "verify everything" trap).
var antiBotNamePhrases = []string{
	"just a moment", "attention required", "access denied", "are you a robot",
	"enable javascript", "captcha", "not found", "forbidden", "cloudflare",
	"page not found", "error 404", "503 service", "request blocked",
}

// trackingParamPrefixes / trackingParams are query keys stripped from links.
var trackingParamPrefixes = []string{"utm_"}

var trackingParams = map[string]struct{}{
	"gclid": {}, "fbclid": {}, "srsltid": {}, "ref": {}, "ref_": {},
	"mc_cid": {}, "mc_eid": {}, "_ga": {}, "igshid": {}, "yclid": {}, "msclkid": {},
}

// ValidateName reports whether a candidate name is acceptable: non-empty, not an
// anti-bot/error string, not merely the site's domain, and of sane length.
func ValidateName(name, host string) bool {
	trimmed := strings.TrimSpace(name)
	if trimmed == "" || len(trimmed) > 512 {
		return false
	}
	if isAntiBotName(trimmed) {
		return false
	}
	return !isDomainOnly(trimmed, host)
}

func isAntiBotName(name string) bool {
	lower := strings.ToLower(name)
	for _, phrase := range antiBotNamePhrases {
		if strings.Contains(lower, phrase) {
			return true
		}
	}
	return false
}

func isDomainOnly(name, host string) bool {
	candidate := normalizeHostLike(name)
	host = normalizeHostLike(host)
	if host == "" {
		return false
	}
	return candidate == host || candidate == strings.TrimSuffix(host, "."+topLevel(host))
}

// normalizeHostLike reduces a string to its bare host form for domain comparison:
// lowercased, scheme + "www." stripped, path/query/fragment dropped. Applied to
// BOTH the candidate name and the host so an anti-bot/error page titled with the
// raw domain ("https://www.aritzia.com/us/en/") is recognized as domain-only and
// rejected — not accepted as a product name.
func normalizeHostLike(value string) string {
	v := strings.ToLower(strings.TrimSpace(value))
	v = strings.TrimPrefix(v, "https://")
	v = strings.TrimPrefix(v, "http://")
	v = strings.TrimPrefix(v, "www.")
	if i := strings.IndexAny(v, "/?#"); i >= 0 {
		v = v[:i]
	}
	return strings.Trim(v, ". ")
}

func topLevel(host string) string {
	if index := strings.LastIndex(host, "."); index >= 0 {
		return host[index+1:]
	}
	return host
}

// ValidatePrice reports whether an amount string is a sane positive price below
// maxPrice (DefaultMaxPrice when maxPrice <= 0).
func ValidatePrice(amount string, maxPrice float64) bool {
	if maxPrice <= 0 {
		maxPrice = DefaultMaxPrice
	}
	value, ok := parsePriceAmount(amount)
	return ok && value > 0 && value < maxPrice
}

// ValidateImageURL reports whether a URL is an acceptable product image: an
// absolute http(s) URL that is not a data URI or an obvious logo/icon/sprite/
// placeholder asset.
func ValidateImageURL(rawURL string) bool {
	trimmed := strings.TrimSpace(rawURL)
	if trimmed == "" || strings.HasPrefix(strings.ToLower(trimmed), "data:") {
		return false
	}
	parsed, err := url.Parse(trimmed)
	if err != nil || (parsed.Scheme != schemeHTTP && parsed.Scheme != schemeHTTPS) || parsed.Host == "" {
		return false
	}
	return !extractors.IsNonProductImageURL(trimmed)
}

// CleanLink strips tracking parameters from a URL, preserving the rest. Returns
// the input unchanged if it cannot be parsed.
func CleanLink(rawURL string) string {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil {
		return rawURL
	}
	query := parsed.Query()
	for key := range query {
		if isTrackingParam(key) {
			query.Del(key)
		}
	}
	parsed.RawQuery = query.Encode()
	parsed.Fragment = ""
	return parsed.String()
}

func isTrackingParam(key string) bool {
	lower := strings.ToLower(key)
	if _, ok := trackingParams[lower]; ok {
		return true
	}
	for _, prefix := range trackingParamPrefixes {
		if strings.HasPrefix(lower, prefix) {
			return true
		}
	}
	return false
}

func parsePriceAmount(amount string) (float64, bool) {
	cleaned := strings.ReplaceAll(strings.TrimSpace(amount), ",", "")
	if cleaned == "" {
		return 0, false
	}
	value, err := strconv.ParseFloat(cleaned, 64)
	if err != nil {
		return 0, false
	}
	return value, true
}
