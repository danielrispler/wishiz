package extractors

import (
	"net/url"
	"strings"
	"testing"

	"github.com/PuerkitoBio/goquery"
)

func parse(t *testing.T, html string) *goquery.Document {
	t.Helper()
	document, err := goquery.NewDocumentFromReader(strings.NewReader(html))
	if err != nil {
		t.Fatalf("parse html: %v", err)
	}
	return document
}

func findPrice(candidates []Candidate) (Candidate, bool) {
	for _, candidate := range candidates {
		if candidate.Field == FieldPrice {
			return candidate, true
		}
	}
	return Candidate{}, false
}

func findField(candidates []Candidate, field Field) (Candidate, bool) {
	for _, candidate := range candidates {
		if candidate.Field == field {
			return candidate, true
		}
	}
	return Candidate{}, false
}

func TestMicrodataExtractsProduct(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.example/p")
	candidates := Microdata(parse(t, `<div itemscope itemtype="http://schema.org/Product">
		<span itemprop="name">Wool Scarf</span>
		<img itemprop="image" src="https://x/scarf.png">
		<span itemprop="price" content="49.99">49.99</span>
		<meta itemprop="priceCurrency" content="USD">
	</div>`), base)

	name, ok := findField(candidates, FieldName)
	if !ok || name.Value != "Wool Scarf" || name.Source != SourceMicrodata {
		t.Fatalf("unexpected name: %+v", name)
	}
	price, ok := findPrice(candidates)
	if !ok || price.Value != "49.99" || price.Currency != "USD" {
		t.Fatalf("unexpected price: %+v", price)
	}
	if image, ok := findField(candidates, FieldImage); !ok || image.Value != "https://x/scarf.png" {
		t.Fatalf("unexpected image: %+v", image)
	}
}

func TestJSStateNextData(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.example/p")
	html := `<script id="__NEXT_DATA__" type="application/json">
		{"props":{"pageProps":{"product":{"name":"Trail Runner","price":"120.00","currencyCode":"USD","image":"https://x/shoe.png"}}}}
	</script>`
	candidates := JSState(parse(t, html), html, base)

	price, ok := findPrice(candidates)
	if !ok || price.Value != "120.00" || price.Currency != "USD" || price.Source != SourceJSState {
		t.Fatalf("unexpected price: %+v", price)
	}
	if name, ok := findField(candidates, FieldName); !ok || name.Value != "Trail Runner" {
		t.Fatalf("unexpected name: %+v", name)
	}
}

func TestJSStateNuxtNestedPrice(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.example/p")
	html := `<script>window.__NUXT__={"data":{"product":{"title":"Hoodie","price":{"amount":"60.00","currencyCode":"EUR"}}}};</script>`
	candidates := JSState(parse(t, html), html, base)

	price, ok := findPrice(candidates)
	if !ok || price.Value != "60.00" || price.Currency != "EUR" {
		t.Fatalf("unexpected price: %+v", price)
	}
}

func TestJSStateIgnoresNonProductMaps(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.example/p")
	html := `<script type="application/json">{"config":{"locale":"en","theme":"dark"}}</script>`
	if candidates := JSState(parse(t, html), html, base); len(candidates) != 0 {
		t.Fatalf("expected no candidates from non-product json, got %+v", candidates)
	}
}

func TestMerchantEmitsMediumPrice(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://vuoriclothing.com/products/villa")
	candidates := Merchant(parse(t,
		`<html><body><span data-testid="productdescriptionprice-price">$128</span></body></html>`), base)

	price, ok := findPrice(candidates)
	if !ok || price.Value != "128" || price.Currency != "USD" || price.Source != SourceMerchant {
		t.Fatalf("unexpected merchant price: %+v", price)
	}
}

func TestMerchantUnknownHostEmitsNothing(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://unknown.example/products/x")
	if candidates := Merchant(parse(t, `<span class="price">$10</span>`), base); len(candidates) != 0 {
		t.Fatalf("expected no merchant candidates for unknown host, got %+v", candidates)
	}
}

func TestBalancedJSONAfterHandlesNestedBracesAndStrings(t *testing.T) {
	t.Parallel()

	got := balancedJSONAfter(`x=window.__NUXT__={"a":{"b":"}"},"c":1};rest`, "__NUXT__")
	if got != `{"a":{"b":"}"},"c":1}` {
		t.Fatalf("unexpected balanced json: %q", got)
	}
}
