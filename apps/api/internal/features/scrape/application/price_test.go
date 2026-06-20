package application

import "testing"

func TestNormalizePrice(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name             string
		raw              string
		expectedAmount   string
		expectedCurrency string
	}{
		{
			name:             "ils suffix",
			raw:              "169.90 ₪",
			expectedAmount:   "169.90",
			expectedCurrency: "ILS",
		},
		{
			name:             "ils prefix",
			raw:              "₪ 599.90",
			expectedAmount:   "599.90",
			expectedCurrency: "ILS",
		},
		{
			name:             "usd code",
			raw:              "USD 19.90",
			expectedAmount:   "19.90",
			expectedCurrency: "USD",
		},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			amount, currency, ok := NormalizePrice(tc.raw)
			if !ok {
				t.Fatalf("expected price to parse")
			}
			if amount != tc.expectedAmount || currency != tc.expectedCurrency {
				t.Fatalf("expected %s %s, got %s %s", tc.expectedAmount, tc.expectedCurrency, amount, currency)
			}
		})
	}
}

// TestNormalizePriceDollarSymbolIsAmbiguous: a bare "$" cannot resolve to a
// concrete currency (USD/CAD/AUD/…), so NormalizePrice reports ok=false rather
// than guessing USD. The amount still parses for downstream inference.
func TestNormalizePriceDollarSymbolIsAmbiguous(t *testing.T) {
	t.Parallel()

	if _, _, ok := NormalizePrice("$19.90"); ok {
		t.Fatal("expected $-only price to not resolve a currency (ambiguous)")
	}
}
