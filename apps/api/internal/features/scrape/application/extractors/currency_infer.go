package extractors

import (
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// regionCurrency maps an ISO-3166 region (lowercased) to its currency, used for
// <html lang>/og:locale inference.
var regionCurrency = map[string]string{
	"us": codeUSD, "gb": codeGBP, "uk": codeGBP, "il": codeILS,
	"de": codeEUR, "fr": codeEUR, "es": codeEUR, "it": codeEUR, "nl": codeEUR, "ie": codeEUR,
	"ca": "CAD", "au": "AUD", "jp": "JPY", "ch": "CHF",
	"se": "SEK", "no": "NOK", "dk": "DKK", "pl": "PLN", "cz": "CZK",
}

// tldCurrency maps a domain TLD to its currency. Generic TLDs (.com/.net/.org)
// are intentionally absent — they are the silent-wrong-price trap, only mapped
// to USD when the caller explicitly opts in.
var tldCurrency = map[string]string{
	"il": codeILS, "uk": codeGBP, "eu": codeEUR,
	"de": codeEUR, "fr": codeEUR, "es": codeEUR, "it": codeEUR, "nl": codeEUR, "ie": codeEUR,
	"ca": "CAD", "au": "AUD", "jp": "JPY", "ch": "CHF",
	"se": "SEK", "no": "NOK", "dk": "DKK", "pl": "PLN", "cz": "CZK",
}

// InferredCurrency derives a currency from page locale signals (<html lang> /
// og:locale) and then the domain TLD, returning a SourceInferred FieldCurrency
// candidate. .com → USD only when allowDotComUSD is set (default OFF: prefer
// needs_review over a fabricated currency).
func InferredCurrency(document *goquery.Document, base *url.URL, allowDotComUSD bool) (Candidate, bool) {
	if code := currencyFromLocale(document); code != "" {
		return inferredCurrencyCandidate(code), true
	}
	if base != nil {
		if code := currencyFromTLD(base.Hostname(), allowDotComUSD); code != "" {
			return inferredCurrencyCandidate(code), true
		}
	}
	return Candidate{}, false
}

func inferredCurrencyCandidate(code string) Candidate {
	return Candidate{Field: FieldCurrency, Value: code, Source: SourceInferred, Inferred: true}
}

func currencyFromLocale(document *goquery.Document) string {
	signals := []string{
		metaContent(document, "og:locale", "property"),
	}
	if lang, ok := document.Find("html").First().Attr("lang"); ok {
		signals = append(signals, lang)
	}
	for _, signal := range signals {
		if region := regionFromLocale(signal); region != "" {
			if code, ok := regionCurrency[region]; ok {
				return code
			}
		}
	}
	return ""
}

// regionFromLocale extracts the region from a locale tag like "en-US", "he_IL"
// or "pt-BR". Returns "" when no region is present (language-only is too
// ambiguous to infer a currency from).
func regionFromLocale(locale string) string {
	normalized := strings.TrimSpace(locale)
	parts := strings.FieldsFunc(normalized, func(r rune) bool { return r == '-' || r == '_' })
	if len(parts) < 2 {
		return ""
	}
	return strings.ToLower(parts[len(parts)-1])
}

func currencyFromTLD(host string, allowDotComUSD bool) string {
	host = strings.ToLower(strings.TrimSuffix(host, "."))
	index := strings.LastIndex(host, ".")
	if index < 0 {
		return ""
	}
	tld := host[index+1:]
	if code, ok := tldCurrency[tld]; ok {
		return code
	}
	if allowDotComUSD && (tld == "com" || tld == "net" || tld == "org") {
		return codeUSD
	}
	return ""
}
