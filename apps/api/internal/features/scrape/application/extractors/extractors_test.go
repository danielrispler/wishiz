package extractors

import (
	"encoding/json"
	"net/url"
	"strings"
	"testing"

	"github.com/PuerkitoBio/goquery"
)

// jsonString JSON-encodes s (with surrounding quotes) so a flight chunk can be
// embedded as the escaped string argument of __next_f.push([N,"…"]), exactly as
// Next.js serializes React Server Component payloads into the SSR HTML.
func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

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

func TestJSStateReactFlightContainerPrice(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://www.wayfair.com/p")

	// Real Wayfair shape: the price lives only in RSC "flight" chunks, split
	// across two __next_f.push calls (each chunk alone is invalid JSON; the
	// concatenation is the product object). primaryPrice.price.value carries the
	// amount + nested currency.code; 4 decoy amounts sit under non-allowlisted
	// keys (listPrice, addOns) and must never surface as a price.
	chunk1 := `2c:{"product":{"name":"Sitarski Writing Desk","pricing":{` +
		`"primaryPrice":{"price":{"value":{"amount":"143.99","currency":{"code":"USD"}}}},` +
		`"listPrice":{"price":{"value":{"amount":"156.99","currency":{"code":"USD"}}}}},`
	chunk2 := `"addOns":[` +
		`{"name":"Assembly","price":{"value":{"amount":"66.99","currency":{"code":"USD"}}}},` +
		`{"name":"Protection","price":{"value":{"amount":"17.29","currency":{"code":"USD"}}}},` +
		`{"name":"Pads","price":{"value":{"amount":"14.29","currency":{"code":"USD"}}}}]}}` + "\n"

	html := `<!doctype html><html><body>` +
		`<script>self.__next_f=self.__next_f||[];self.__next_f.push([0])</script>` +
		`<script>self.__next_f.push([1,` + jsonString(chunk1) + `])</script>` +
		`<script>self.__next_f.push([1,` + jsonString(chunk2) + `])</script>` +
		`</body></html>`

	candidates := JSState(parse(t, html), html, base)

	price, ok := findPrice(candidates)
	if !ok || price.Value != "143.99" || price.Currency != "USD" || price.Source != SourceJSState {
		t.Fatalf("expected flight price 143.99/USD/js_state, got %+v (ok=%v)", price, ok)
	}
	for _, candidate := range candidates {
		if candidate.Field == FieldPrice && candidate.Value != "143.99" {
			t.Fatalf("decoy amount leaked as a price candidate: %+v", candidate)
		}
	}
}

func TestReconstructFlightBlobConcatenatesChunks(t *testing.T) {
	t.Parallel()

	chunk1 := `a:{"product":{"name":"Desk",`
	chunk2 := `"sku":"123"}}` + "\n"
	html := `<script>self.__next_f.push([0])</script>` +
		`<script>self.__next_f.push([1,` + jsonString(chunk1) + `])</script>` +
		`<script>self.__next_f.push([1,` + jsonString(chunk2) + `])</script>`

	if got := reconstructFlightBlob(html); got != chunk1+chunk2 {
		t.Fatalf("blob = %q, want concatenation of both chunks", got)
	}
}

func TestContainerPriceIgnoresBareAmounts(t *testing.T) {
	t.Parallel()

	// A full Money under a NON-allowlisted container key must never vote on price:
	// disambiguation is by container key, not by scanning every amount.
	node := map[string]any{
		"shippingPrice": map[string]any{
			"price": map[string]any{
				"value": map[string]any{"amount": "9.99", "currency": map[string]any{"code": "USD"}},
			},
		},
	}
	if got := containerPriceCandidates(node, map[string]struct{}{}); len(got) != 0 {
		t.Fatalf("non-allowlisted container must not emit a price, got %+v", got)
	}
}

func TestContainerPriceRequiresCurrency(t *testing.T) {
	t.Parallel()

	// Allowlisted container, real amount, but NO currency anywhere in the Money:
	// the hard guard drops it (never assigns a bare $).
	node := map[string]any{
		"primaryPrice": map[string]any{
			"price": map[string]any{"value": map[string]any{"amount": "143.99"}},
		},
	}
	if got := containerPriceCandidates(node, map[string]struct{}{}); len(got) != 0 {
		t.Fatalf("currency-less Money must not emit a price, got %+v", got)
	}
}

func TestJSStateFlightGenericNamePrice(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://store.example/p")

	// Part A (generic transport): a flight island that co-locates a name with a
	// flat/one-level price benefits with zero schema knowledge — not just the
	// container-keyed Wayfair shape.
	chunk := `7:{"product":{"name":"Generic Widget","price":"42.00","currencyCode":"USD"}}` + "\n"
	html := `<script>self.__next_f.push([1,` + jsonString(chunk) + `])</script>`

	candidates := JSState(parse(t, html), html, base)

	price, ok := findPrice(candidates)
	if !ok || price.Value != "42.00" || price.Currency != "USD" || price.Source != SourceJSState {
		t.Fatalf("expected generic flight price 42.00/USD, got %+v (ok=%v)", price, ok)
	}
	if name, ok := findField(candidates, FieldName); !ok || name.Value != "Generic Widget" {
		t.Fatalf("expected generic flight name, got %+v (ok=%v)", name, ok)
	}
}

func TestMerchantEmitsMediumPrice(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://vuoriclothing.com/products/villa")
	candidates := Merchant(parse(t,
		`<html><body><span data-testid="productdescriptionprice-price">$128</span></body></html>`), base)

	// "$128" carries no concrete currency ($ is ambiguous), so the merchant
	// candidate has an empty Currency and relies on downstream inference.
	price, ok := findPrice(candidates)
	if !ok || price.Value != "128" || price.Currency != "" || price.Source != SourceMerchant {
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

func TestMerchantSelectorsForMatchesHostNotSubstring(t *testing.T) {
	t.Parallel()

	// A look-alike host must NOT borrow a real merchant's selectors via a
	// substring match.
	if got := merchantSelectorsFor("fake-nike.com"); got != nil {
		t.Errorf("fake-nike.com must not match nike.com selectors, got %v", got)
	}
	if got := merchantSelectorsFor("nikexcom.evil.com"); got != nil {
		t.Errorf("nikexcom.evil.com must not match, got %v", got)
	}
	// Exact host and legitimate subdomains still match.
	if merchantSelectorsFor("nike.com") == nil {
		t.Error("exact host nike.com should match")
	}
	if merchantSelectorsFor("www.nike.com") == nil {
		t.Error("subdomain www.nike.com should match")
	}
}

func TestBalancedJSONAfterHandlesNestedBracesAndStrings(t *testing.T) {
	t.Parallel()

	got := balancedJSONAfter(`x=window.__NUXT__={"a":{"b":"}"},"c":1};rest`, "__NUXT__")
	if got != `{"a":{"b":"}"},"c":1}` {
		t.Fatalf("unexpected balanced json: %q", got)
	}
}

func TestBalancedJSONAfterIIFE(t *testing.T) {
	t.Parallel()

	// window.__NUXT__=(function(){return {...}}()) — the first { after the marker
	// is the function body, not the product object; must skip to the real return.
	got := balancedJSONAfter(`window.__NUXT__=(function(){return {"name":"Lamp"}}());more`, "__NUXT__")
	if got != `{"name":"Lamp"}` {
		t.Fatalf("IIFE: got %q, want the returned product object", got)
	}
}

func TestBalancedJSONAfterIgnoresReturnInsideString(t *testing.T) {
	t.Parallel()

	// A string literal containing `return {fake}` must not fool the scanner — it
	// must find the real return object that follows the string.
	got := balancedJSONAfter(`__NUXT__=(function(){var s="don't return {fake}";return {"name":"Real"}}())`, "__NUXT__")
	if got != `{"name":"Real"}` {
		t.Fatalf("got %q, want the real object not the fake one inside the string", got)
	}
}

func TestBalancedJSONAfterDirectAssignment(t *testing.T) {
	t.Parallel()

	got := balancedJSONAfter(`window.__NUXT__={"name":"Lamp"};x`, "__NUXT__")
	if got != `{"name":"Lamp"}` {
		t.Fatalf("direct assignment: got %q", got)
	}
}

func TestJSStateExtractsIIFEWrappedNuxt(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.example/p")
	html := `<script>window.__NUXT__=(function(){return ` +
		`{"product":{"name":"Lamp","price":"40","currency":"USD"}}}())</script>`
	candidates := JSState(parse(t, html), html, base)
	if _, ok := findPrice(candidates); !ok {
		t.Fatalf("expected a price candidate from IIFE-wrapped __NUXT__, got %+v", candidates)
	}
}
