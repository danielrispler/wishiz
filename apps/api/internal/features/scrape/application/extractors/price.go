package extractors

import (
	"regexp"
	"strings"
	"unicode"
)

// amountPattern captures the full numeric span including both grouping and
// decimal separators (e.g. "1.299,00"); parseAmount then owns the locale
// interpretation. It deliberately does NOT anchor the decimal part, because the
// decimal separator differs by locale and is resolved downstream.
var amountPattern = regexp.MustCompile(`\d[\d.,]*\d|\d`)

// Shared currency-code constants (also keep goconst happy across the maps below
// and the inference tables).
const (
	codeUSD = "USD"
	codeEUR = "EUR"
	codeGBP = "GBP"
	codeILS = "ILS"
)

var currencyCodeAliases = map[string]string{
	codeUSD: codeUSD,
	codeEUR: codeEUR,
	codeGBP: codeGBP,
	codeILS: codeILS,
	"NIS":   codeILS,
}

// currencySymbolAliases maps only UNAMBIGUOUS symbols. "$" is deliberately
// absent: it is shared by USD/CAD/AUD/NZD/… so a bare "$" cannot be resolved to
// a concrete currency. A $-only amount keeps an empty currency and flows to the
// inference step (locale/TLD), and to needs_review if that can't decide —
// matching the SCRAPE_INFER_DOTCOM_USD "silent-wrong-price trap" stance.
var currencySymbolAliases = map[string]string{
	"€": codeEUR,
	"£": codeGBP,
	"₪": codeILS,
}

// NormalizePrice extracts the amount and (if present) currency from a raw price
// string. ok is false when no amount is found OR no currency could be detected.
// Currency-less amounts are handled by the consensus engine (currency
// inference), not here.
func NormalizePrice(raw string) (amount string, currency string, ok bool) {
	amount, currency, _, ok = normalizePriceParts(raw)
	return amount, currency, ok && currency != ""
}

// normalizePriceParts is like NormalizePrice but also reports whether an amount
// was found independent of currency, so callers (consensus) can keep an
// amount-without-currency candidate for inference.
func normalizePriceParts(raw string) (amount string, currency string, hasAmount bool, ok bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", "", false, false
	}

	matches := amountPattern.FindString(trimmed)
	if matches == "" {
		return "", "", false, false
	}

	normalizedAmount, amountOK := parseAmount(matches)
	if !amountOK {
		return "", "", false, false
	}

	explicitCode := detectCurrencyCode(trimmed)
	symbolCode := detectCurrencySymbol(trimmed)

	switch {
	case explicitCode != "":
		return normalizedAmount, explicitCode, true, true
	case symbolCode != "":
		return normalizedAmount, symbolCode, true, true
	default:
		return normalizedAmount, "", true, true
	}
}

// parseAmount interprets a raw numeric span (already stripped of currency text
// by amountPattern) into a canonical "1234.56"/"1234" amount string, resolving
// the grouping-vs-decimal ambiguity per locale. A separator (".", ",") is the
// decimal point only when it occurs exactly once and is followed by 1–2 digits;
// otherwise it is a thousands grouping separator and is removed. When both
// separators appear, the last-occurring one is the decimal and the other is
// grouping. ok is false when no digits survive.
func parseAmount(raw string) (string, bool) {
	s := strings.Trim(strings.TrimSpace(raw), ".,")
	if s == "" {
		return "", false
	}

	dot := strings.Contains(s, ".")
	comma := strings.Contains(s, ",")
	switch {
	case dot && comma:
		if strings.LastIndexByte(s, ',') > strings.LastIndexByte(s, '.') {
			// Comma is the decimal separator; dot is grouping.
			s = strings.ReplaceAll(s, ".", "")
			s = strings.ReplaceAll(s, ",", ".")
		} else {
			// Dot is the decimal separator; comma is grouping.
			s = strings.ReplaceAll(s, ",", "")
		}
	case comma:
		if isDecimalSep(s, ',') {
			s = strings.ReplaceAll(s, ",", ".")
		} else {
			s = strings.ReplaceAll(s, ",", "")
		}
	case dot:
		if !isDecimalSep(s, '.') {
			s = strings.ReplaceAll(s, ".", "")
		}
	}

	if s == "" {
		return "", false
	}
	return s, true
}

// isDecimalSep reports whether sep behaves as a decimal point in s: it must
// occur exactly once and be followed by 1 or 2 digits. Any other shape (absent,
// repeated, or 3+ trailing digits like "1.299") is a grouping separator.
func isDecimalSep(s string, sep byte) bool {
	i := strings.IndexByte(s, sep)
	if i < 0 || i != strings.LastIndexByte(s, sep) {
		return false
	}
	frac := len(s) - i - 1
	return frac >= 1 && frac <= 2
}

// joinPrice combines a currency code and amount into a single raw string that
// NormalizePrice can re-parse (currency detection works off the combined text).
func joinPrice(currency, amount string) string {
	return strings.TrimSpace(strings.TrimSpace(currency) + " " + strings.TrimSpace(amount))
}

// newPriceCandidate builds a FieldPrice Candidate from raw price text. An
// explicit currency code (e.g. JSON-LD priceCurrency) wins over one detected
// in the text. ok is false when no amount can be parsed. A candidate may carry
// an amount with an empty Currency — the consensus engine decides what to do
// with it (drop, or infer the currency).
func newPriceCandidate(source SourceName, explicitCurrency, raw string) (Candidate, bool) {
	amount, detected, hasAmount, _ := normalizePriceParts(raw)
	if !hasAmount {
		return Candidate{}, false
	}
	currency := strings.ToUpper(strings.TrimSpace(explicitCurrency))
	if currency == "" {
		currency = detected
	}
	return Candidate{
		Field:    FieldPrice,
		Value:    amount,
		Currency: currency,
		Source:   source,
		Raw:      normalizeText(raw),
	}, true
}

// NewShopifyPriceCandidate builds an authoritative Shopify FieldPrice candidate
// from an already-parsed amount and (possibly empty) currency code.
func NewShopifyPriceCandidate(amount, currency string) Candidate {
	candidate, _ := newPriceCandidate(SourceShopify, currency, joinPrice(currency, amount))
	candidate.Field = FieldPrice
	return candidate
}

// detectCurrencyCode matches a currency code on whole-token boundaries, not as
// a substring — so "UTENSILS" does not match ILS. Tokens are scanned in
// document order and the first matching alias wins, which is deterministic
// (unlike ranging a map, which the previous implementation did).
func detectCurrencyCode(value string) string {
	for _, token := range tokenizeAlnum(value) {
		if code, ok := currencyCodeAliases[strings.ToUpper(token)]; ok {
			return code
		}
	}
	return ""
}

// tokenizeAlnum splits s into maximal alphanumeric runs, dropping all separators
// and punctuation. This is what gives detectCurrencyCode its word boundaries.
func tokenizeAlnum(s string) []string {
	return strings.FieldsFunc(s, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
}

func detectCurrencySymbol(value string) string {
	for symbol, code := range currencySymbolAliases {
		if strings.Contains(value, symbol) {
			return code
		}
	}
	return ""
}
