package extractors

import "testing"

// TestParseAmount pins the locale-aware decimal parsing. The dangerous failures
// are the European comma-decimal ("169,90" must not become 16990) and the
// 3-digit dot-grouping case ("1.299" is 1299, not 1.299), so both are covered.
func TestParseAmount(t *testing.T) {
	t.Parallel()

	cases := []struct {
		raw  string
		want string
		ok   bool
	}{
		{"169,90", "169.90", true},     // comma decimal
		{"1.299,00", "1299.00", true},  // EU: dot grouping, comma decimal
		{"1,299.00", "1299.00", true},  // US: comma grouping, dot decimal
		{"1,234.56", "1234.56", true},  // US grouping + decimal
		{"15.00", "15.00", true},       // plain dot decimal
		{"1.299", "1299", true},        // 3-digit after dot -> grouping
		{"1.29", "1.29", true},         // 2-digit after dot -> decimal
		{"1,299", "1299", true},        // 3-digit after comma -> grouping
		{"129", "129", true},           // integer
		{"1.234.567", "1234567", true}, // multi-dot grouping
		{"", "", false},                // empty
	}
	for _, tc := range cases {
		got, ok := parseAmount(tc.raw)
		if ok != tc.ok || got != tc.want {
			t.Errorf("parseAmount(%q) = (%q, %v), want (%q, %v)", tc.raw, got, ok, tc.want, tc.ok)
		}
	}
}

// TestNormalizePriceEUComma confirms the locale parsing is wired through the
// public path: a European-formatted price reaches the amount unmangled.
func TestNormalizePriceEUComma(t *testing.T) {
	t.Parallel()

	amount, currency, ok := NormalizePrice("1.299,00 €")
	if !ok || amount != "1299.00" || currency != codeEUR {
		t.Fatalf("NormalizePrice(EU comma) = (%q, %q, %v), want (1299.00, EUR, true)", amount, currency, ok)
	}
}

// TestCurrencySymbolDetection: $ is ambiguous (USD/CAD/AUD/…) and must NOT
// resolve to a concrete currency — it falls through to inference. Unambiguous
// symbols still map directly.
func TestCurrencySymbolDetection(t *testing.T) {
	t.Parallel()

	if got := detectCurrencySymbol("$129"); got != "" {
		t.Errorf("detectCurrencySymbol($) = %q, want empty (ambiguous)", got)
	}
	for _, tc := range []struct{ raw, want string }{
		{"€10", codeEUR}, {"£10", codeGBP}, {"₪10", codeILS},
	} {
		if got := detectCurrencySymbol(tc.raw); got != tc.want {
			t.Errorf("detectCurrencySymbol(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

// TestNormalizePriceDollarHasNoCurrency: a $-only price yields an amount with an
// empty currency (ok=false), so the consensus engine routes it to inference /
// needs_review rather than silently assuming USD.
func TestNormalizePriceDollarHasNoCurrency(t *testing.T) {
	t.Parallel()

	amount, currency, ok := NormalizePrice("$129")
	if currency != "" || ok || amount != "129" {
		t.Fatalf("NormalizePrice($129) = (%q, %q, %v), want (129, \"\", false)", amount, currency, ok)
	}
}

// TestDetectCurrencyCode pins word-boundary matching (not substring) and
// deterministic alias ordering. "UTENSILS" must NOT match ILS; a real "ILS"
// token must; and overlapping codes resolve to a single documented winner
// regardless of map iteration order.
func TestDetectCurrencyCode(t *testing.T) {
	t.Parallel()

	cases := []struct {
		raw  string
		want string
	}{
		{"UTENSILS", ""},     // substring, not a token — must not match ILS
		{"100 ILS", codeILS}, // real token
		{"NIS 50", codeILS},  // alias token
		{"Price: USD 5", codeUSD},
		{"49.99 EUR", codeEUR},
		{"no code here", ""},
	}
	for _, tc := range cases {
		if got := detectCurrencyCode(tc.raw); got != tc.want {
			t.Errorf("detectCurrencyCode(%q) = %q, want %q", tc.raw, got, tc.want)
		}
	}
}

// TestDetectCurrencyCodeDeterministic: when two distinct codes are present, the
// result is stable across runs (no map-order nondeterminism). The first code in
// document order wins.
func TestDetectCurrencyCodeDeterministic(t *testing.T) {
	t.Parallel()

	const raw = "USD 5 / EUR 4"
	first := detectCurrencyCode(raw)
	if first != codeUSD {
		t.Fatalf("detectCurrencyCode(%q) = %q, want USD (first in order)", raw, first)
	}
	for i := 0; i < 50; i++ {
		if got := detectCurrencyCode(raw); got != first {
			t.Fatalf("detectCurrencyCode nondeterministic: got %q then %q", first, got)
		}
	}
}
