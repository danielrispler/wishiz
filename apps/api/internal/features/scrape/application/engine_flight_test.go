package application

import (
	"encoding/json"
	"testing"
)

// flightScript wraps a flight chunk in the __next_f.push([1,"…"]) SSR form Next.js
// emits, JSON-escaping the chunk exactly as the browser receives it.
func flightScript(chunk string) string {
	b, _ := json.Marshal(chunk)
	return `<script>self.__next_f.push([1,` + string(b) + `])</script>`
}

// Regression (wayfair.com): Wayfair serves NO Product JSON-LD and NO og:price —
// the real price lives only in React Server Component "flight" chunks
// (primaryPrice.price.value.amount + currency.code). With the generic flight
// reader, the container-keyed price (MEDIUM, single decent source) plus its
// explicit currency (HIGH) and the <h1> name (MEDIUM) clear the relaxed
// auto-complete gate, turning a chronic needs_review into auto_complete.
func TestEngineWayfairFlightPriceAutoCompletes(t *testing.T) {
	t.Parallel()

	chunk := `2c:{"product":{"name":"Sitarski Writing Desk","pricing":{` +
		`"primaryPrice":{"price":{"value":{"amount":"143.99","currency":{"code":"USD"}}}},` +
		`"listPrice":{"price":{"value":{"amount":"156.99","currency":{"code":"USD"}}}}}}}` + "\n"

	// No Product JSON-LD and no og:title (the real Wayfair shape): the <h1> is the
	// name source, and the obfuscated PriceDisplay span renders the visible amount.
	product := reconcile(t, "https://www.wayfair.com/furniture/pdp/desk-w110883108.html",
		`<html><head></head><body>`+
			`<h1>Sitarski Writing Desk</h1>`+
			`<div data-test-id="PriceDisplay"><span class="price">$143.99</span></div>`+
			flightScript(chunk)+
			`</body></html>`)

	if product.PriceAmount != "143.99" || product.PriceCurrency != "USD" {
		t.Fatalf("expected 143.99 USD, got %q %q (reasons %v)",
			product.PriceAmount, product.PriceCurrency, product.Reasons)
	}
	if product.Fields.Price != ConfidenceMedium {
		t.Fatalf("expected price MEDIUM (single decent flight source), got %q", product.Fields.Price)
	}
	if product.Fields.Currency != ConfidenceHigh {
		t.Fatalf("expected currency HIGH (explicit code), got %q", product.Fields.Currency)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
}

// Regression (wayfair.com, real page): Wayfair serves THREE differing name
// sources for the same product — the <h1> is the clean core ("Christye Full
// Length Mirror …"), while og:title and <title> add a brand prefix ("Wade Logan®")
// and a site/review suffix ("… & Reviews | Wayfair"). The h1 is a substring of the
// og:title — the SAME product, not a contradiction — yet they grouped as two decent
// names and forced name_conflict → needs_review. A name conflict where one value
// contains the other must resolve (display the clean h1) and auto-complete.
func TestEngineWayfairNameVariantsResolveToCleanName(t *testing.T) {
	t.Parallel()

	const core = "Christye Full Length Mirror 63x24 Irregular Wavy Arched Floor Mirror"
	chunk := `2c:{"product":{"name":"` + core + `","pricing":{"primaryPrice":` +
		`{"price":{"value":{"amount":"143.99","currency":{"code":"USD"}}}}}}}` + "\n"

	product := reconcile(t, "https://www.wayfair.com/home/pdp/christye-mirror-ctiu1014.html?piid=124594576",
		`<html><head>`+
			`<meta property="og:title" content="Wade Logan® `+core+` &amp; Reviews | Wayfair">`+
			`<meta property="og:image" content="https://assets.wfcdn.com/im/mirror.jpg">`+
			`<title>Wade Logan® `+core+` &amp; Reviews | Wayfair</title>`+
			`</head><body>`+
			`<h1>`+core+`</h1>`+
			`<div data-test-id="PriceDisplay">$143.99</div>`+
			flightScript(chunk)+
			`</body></html>`)

	if product.Fields.Name == ConfidenceConflict {
		t.Fatalf("name variants (h1 ⊂ og:title) must not conflict, got reasons=%v", product.Reasons)
	}
	if product.Name != core {
		t.Fatalf("expected clean h1 name %q, got %q", core, product.Name)
	}
	if product.PriceAmount != "143.99" || product.PriceCurrency != "USD" {
		t.Fatalf("expected 143.99 USD, got %q %q", product.PriceAmount, product.PriceCurrency)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
}

// Regression (wayfair.com, real page): a Wayfair PDP carries MANY primaryPrice
// flight nodes — the main listing PLUS every add-on/related listing (protection
// plan, assembly, wall anchor), each with its OWN pricing.primaryPrice. Harvesting
// all of them yields 4 conflicting decent price groups → needs_review, and the
// ascending tie-break prefills the cheapest add-on ($14.29) — a WRONG price. The
// shopper-facing main price renders in the FIRST [data-test-id="PriceDisplay"]
// element ($143.99); that displayed price must disambiguate the flight range to
// the correct amount and auto-complete.
func TestEngineWayfairMultiPrimaryPriceDisambiguatedByDisplayed(t *testing.T) {
	t.Parallel()

	chunk := `2c:{"listings":[` +
		`{"name":"Christye Full Length Mirror","pricing":{"primaryPrice":` +
		`{"price":{"value":{"amount":"143.99","currency":{"code":"USD"}}}}}},` +
		`{"name":"Protection Plan","pricing":{"primaryPrice":` +
		`{"price":{"value":{"amount":"66.99","currency":{"code":"USD"}}}}}},` +
		`{"name":"Assembly","pricing":{"primaryPrice":` +
		`{"price":{"value":{"amount":"17.29","currency":{"code":"USD"}}}}}},` +
		`{"name":"Wall Anchor","pricing":{"primaryPrice":` +
		`{"price":{"value":{"amount":"14.29","currency":{"code":"USD"}}}}}}` +
		`]}` + "\n"

	product := reconcile(t, "https://www.wayfair.com/home/pdp/christye-mirror-ctiu1014.html?piid=124594576",
		`<html><head></head><body>`+
			`<h1>Christye Full Length Mirror</h1>`+
			// Main price block renders first; the rest are list/related prices.
			`<div data-test-id="PriceDisplay">$143.99</div>`+
			`<div data-test-id="PriceDisplay">$156.99</div>`+
			`<div data-test-id="PriceDisplay">$97.99</div>`+
			flightScript(chunk)+
			`</body></html>`)

	if product.PriceAmount != "143.99" || product.PriceCurrency != "USD" {
		t.Fatalf("expected main price 143.99 USD, got %q %q (reasons %v)",
			product.PriceAmount, product.PriceCurrency, product.Reasons)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
}
