package application

import "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"

// NormalizePrice extracts the amount and currency from a raw price string. It
// forwards to the extractors package, which owns price parsing so the leaf
// extractors can reuse it without importing this package. ok is false unless
// both an amount and a currency are detected.
func NormalizePrice(raw string) (amount string, currency string, ok bool) {
	return extractors.NormalizePrice(raw)
}
