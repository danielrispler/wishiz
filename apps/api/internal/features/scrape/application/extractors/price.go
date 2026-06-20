package extractors

import (
	"regexp"
	"strings"
)

var amountPattern = regexp.MustCompile(`\d[\d,]*(?:\.\d{1,2})?`)

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

var currencySymbolAliases = map[string]string{
	"$": codeUSD,
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

	normalizedAmount := strings.TrimSpace(strings.ReplaceAll(matches, ",", ""))
	if normalizedAmount == "" {
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

func detectCurrencyCode(value string) string {
	upper := strings.ToUpper(value)
	for alias, code := range currencyCodeAliases {
		if strings.Contains(upper, alias) {
			return code
		}
	}
	return ""
}

func detectCurrencySymbol(value string) string {
	for symbol, code := range currencySymbolAliases {
		if strings.Contains(value, symbol) {
			return code
		}
	}
	return ""
}
