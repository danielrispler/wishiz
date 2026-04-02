package application

import (
	"regexp"
	"strings"
)

var amountPattern = regexp.MustCompile(`\d[\d,]*(?:\.\d{1,2})?`)

var currencyCodeAliases = map[string]string{
	"USD": "USD",
	"EUR": "EUR",
	"GBP": "GBP",
	"ILS": "ILS",
	"NIS": "ILS",
}

var currencySymbolAliases = map[string]string{
	"$": "USD",
	"€": "EUR",
	"£": "GBP",
	"₪": "ILS",
}

func NormalizePrice(raw string) (amount string, currency string, ok bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", "", false
	}

	matches := amountPattern.FindString(trimmed)
	if matches == "" {
		return "", "", false
	}

	normalizedAmount := strings.ReplaceAll(matches, ",", "")
	normalizedAmount = strings.TrimSpace(normalizedAmount)
	if normalizedAmount == "" {
		return "", "", false
	}

	explicitCode := detectCurrencyCode(trimmed)
	symbolCode := detectCurrencySymbol(trimmed)

	switch {
	case explicitCode != "":
		return normalizedAmount, explicitCode, true
	case symbolCode != "":
		return normalizedAmount, symbolCode, true
	default:
		return "", "", false
	}
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
