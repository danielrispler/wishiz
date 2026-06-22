package shopify

import (
	"net/url"
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

func price(candidates []extractors.Candidate) (extractors.Candidate, bool) {
	for _, candidate := range candidates {
		if candidate.Field == extractors.FieldPrice {
			return candidate, true
		}
	}
	return extractors.Candidate{}, false
}

func field(candidates []extractors.Candidate, f extractors.Field) string {
	for _, candidate := range candidates {
		if candidate.Field == f {
			return candidate.Value
		}
	}
	return ""
}

func TestParseProductJSON(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://store.example")
	data := []byte(`{"product":{"title":"Cotton Tee","image":{"src":"https://cdn/tee.jpg"},
		"variants":[{"price":"25.00","presentment_prices":[{"price":{"amount":"25.00","currency_code":"usd"}}]}]}}`)

	candidates := parseProductJSON(data, false, base)
	if name := field(candidates, extractors.FieldName); name != "Cotton Tee" {
		t.Fatalf("unexpected name: %q", name)
	}
	if image := field(candidates, extractors.FieldImage); image != "https://cdn/tee.jpg" {
		t.Fatalf("unexpected image: %q", image)
	}
	p, ok := price(candidates)
	if !ok || p.Value != "25.00" || p.Currency != "USD" || p.Source != extractors.SourceShopify {
		t.Fatalf("unexpected price: %+v", p)
	}
}

// Regression (apc-us.com): a .json variant with no presentment_prices still
// carries price_currency on the bare variant. Discarding it emitted a
// currency-less price that conflicted with the page's json_ld USD price and
// forced needs_review. The probe must read price_currency.
func TestParseProductJSONBareVariantCurrency(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://store.example")
	data := []byte(`{"product":{"title":"Grace Mini Bag","image":{"src":"https://cdn/bag.jpg"},
		"variants":[{"price":"375.00","price_currency":"usd"}]}}`)

	candidates := parseProductJSON(data, false, base)
	p, ok := price(candidates)
	if !ok || p.Value != "375.00" || p.Currency != "USD" || p.Source != extractors.SourceShopify {
		t.Fatalf("unexpected price: %+v (ok=%v)", p, ok)
	}
}

func TestParseProductJSDotJSCentsNoCurrencySkipsPrice(t *testing.T) {
	t.Parallel()

	// .js cents with no presentment currency: we can know neither the decimal
	// exponent (JPY=0, USD=2) nor the label, so emitting a scaled price is a
	// silent-wrong-price risk. Skip the price; title/image are still emitted.
	base, _ := url.Parse("https://store.example")
	data := []byte(`{"title":"Cap","featured_image":"//cdn/cap.jpg","variants":[{"price":2500}]}`)

	candidates := parseProductJSON(data, true, base)
	if image := field(candidates, extractors.FieldImage); image != "https://cdn/cap.jpg" {
		t.Fatalf("unexpected image: %q", image)
	}
	if name := field(candidates, extractors.FieldName); name != "Cap" {
		t.Fatalf("unexpected name: %q", name)
	}
	if p, ok := price(candidates); ok {
		t.Fatalf("expected no price from currency-less .js cents, got %+v", p)
	}
}

func TestParseProductJSONPresentmentJPYUnscaled(t *testing.T) {
	t.Parallel()

	// presentment amount is already major-unit; a zero-decimal currency like JPY
	// must NOT be divided by 100.
	base, _ := url.Parse("https://store.example")
	data := []byte(`{"product":{"title":"Mug","variants":[{"price":1500,
		"presentment_prices":[{"price":{"amount":"1500","currency_code":"jpy"}}]}]}}`)

	candidates := parseProductJSON(data, true, base)
	p, ok := price(candidates)
	if !ok || p.Value != "1500" || p.Currency != "JPY" {
		t.Fatalf("expected unscaled 1500 JPY, got %+v (ok=%v)", p, ok)
	}
}

func TestProductHandle(t *testing.T) {
	t.Parallel()

	cases := map[string]string{
		"https://s.example/products/blue-tee":             "blue-tee",
		"https://s.example/collections/sale/products/cap": "cap",
		"https://s.example/products/blue-tee.json":        "blue-tee",
		"https://s.example/category/item":                 "",
	}
	for raw, want := range cases {
		u, _ := url.Parse(raw)
		got, ok := productHandle(u)
		if want == "" && ok {
			t.Fatalf("%s: expected no handle, got %q", raw, got)
		}
		if want != "" && got != want {
			t.Fatalf("%s: expected handle %q, got %q", raw, want, got)
		}
	}
}

func TestIsShopify(t *testing.T) {
	t.Parallel()

	if !IsShopify(`<script src="https://cdn.shopify.com/x.js"></script>`, nil) {
		t.Fatalf("expected cdn.shopify.com to be detected")
	}
	header := map[string][]string{"X-Shopify-Stage": {"production"}}
	if !IsShopify("", header) {
		t.Fatalf("expected X-Shopify header to be detected")
	}
	if IsShopify("<html>plain</html>", nil) {
		t.Fatalf("did not expect detection on a plain page")
	}
}
