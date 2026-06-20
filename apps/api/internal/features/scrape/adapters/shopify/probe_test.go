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

func TestParseProductJSDotJSCents(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://store.example")
	data := []byte(`{"title":"Cap","featured_image":"//cdn/cap.jpg","variants":[{"price":2500}]}`)

	candidates := parseProductJSON(data, true, base)
	if image := field(candidates, extractors.FieldImage); image != "https://cdn/cap.jpg" {
		t.Fatalf("unexpected image: %q", image)
	}
	p, ok := price(candidates)
	if !ok || p.Value != "25.00" {
		t.Fatalf("expected cents->major 25.00, got %+v", p)
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
