package application

import (
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// Regression (apc-us.com / Shopify): the Shopify probe emits an authoritative
// price with the right amount but an EMPTY currency (it never carried the
// variant's price_currency). json_ld on the same page carries 375.00 USD. The
// two authoritative groups — "375.00\x00" and "375.00\x00USD" — were counted as
// a disagreement, flagging price AND currency as conflict and forcing
// needs_review on a product every source agrees is $375 USD. A currency-less
// amount is LESS specific, not contradictory: it must not conflict with the
// same amount that does carry a currency.
func TestEngineCurrencylessPriceDoesNotConflictWithSameAmount(t *testing.T) {
	t.Parallel()
	engine := NewEngine(EngineConfig{})
	const pageURL = "https://shop.example/products/bag"
	candidates := []extractors.Candidate{
		{Field: extractors.FieldName, Value: "Grace Mini Bag", Source: extractors.SourceJSONLD, Raw: "Grace Mini Bag"},
		{Field: extractors.FieldImage, Value: "https://cdn.example/bag.jpg", Source: extractors.SourceJSONLD,
			Raw: "https://cdn.example/bag.jpg"},
		{Field: extractors.FieldPrice, Value: "375.00", Currency: "USD", Source: extractors.SourceJSONLD, Raw: "375.00"},
		{Field: extractors.FieldCurrency, Value: "USD", Source: extractors.SourceJSONLD, Raw: "USD"},
		// Shopify probe: same amount, no currency — the bug trigger.
		extractors.NewShopifyPriceCandidate("375.00", ""),
	}

	product := engine.Reconcile(candidates, pageURL)

	if product.Fields.Price == ConfidenceConflict || product.Fields.Currency == ConfidenceConflict {
		t.Fatalf("currency-less same-amount price must not conflict: price=%s currency=%s reasons=%v",
			product.Fields.Price, product.Fields.Currency, product.Reasons)
	}
	if product.PriceAmount != "375.00" || product.PriceCurrency != "USD" {
		t.Fatalf("expected 375.00 USD, got %q %q", product.PriceAmount, product.PriceCurrency)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q reasons=%v", product.Verdict, product.Reasons)
	}
}

// Guardrail: two authoritative sources reporting the SAME amount in DIFFERENT
// known currencies (375 USD vs 375 EUR) is a genuine conflict and must still
// route to review — the empty-currency relaxation must not swallow it.
func TestEngineSameAmountDifferentKnownCurrenciesStillConflict(t *testing.T) {
	t.Parallel()
	engine := NewEngine(EngineConfig{})
	const pageURL = "https://shop.example/products/bag"
	candidates := []extractors.Candidate{
		{Field: extractors.FieldName, Value: "Grace Mini Bag", Source: extractors.SourceJSONLD, Raw: "Grace Mini Bag"},
		{Field: extractors.FieldPrice, Value: "375.00", Currency: "USD", Source: extractors.SourceJSONLD, Raw: "375.00"},
		{Field: extractors.FieldPrice, Value: "375.00", Currency: "EUR", Source: extractors.SourceOpenGraph, Raw: "375.00"},
	}

	product := engine.Reconcile(candidates, pageURL)

	if product.Fields.Price != ConfidenceConflict {
		t.Fatalf("expected price CONFLICT for USD vs EUR, got %q", product.Fields.Price)
	}
	if product.Verdict == VerdictAutoComplete {
		t.Fatalf("expected needs_review on a true currency conflict, got auto_complete")
	}
}

// Regression (westelm): og:image and the JSON-LD image are two renditions of the
// SAME product photo — identical path, different size/crop suffix (…-o.jpg vs
// …-d.jpg). The old scraper trusted one image and auto-completed. The rewrite's
// consensus flagged them as a "conflict" (two authoritative sources, different
// URL) and forced needs_review. Any valid product image is acceptable, so a
// differing rendition must NOT block auto-complete.
func TestEngineDifferentImageRenditionsAutoComplete(t *testing.T) {
	t.Parallel()
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<script type="application/ld+json">{
			"@type":"Product","name":"Norre Console",
			"image":"https://cdn.example/norre-68-80-o.jpg",
			"offers":{"@type":"Offer","price":"799","priceCurrency":"USD"}
		}</script>
		<meta property="og:image" content="https://cdn.example/norre-68-80-d.jpg">
		</head><body></body></html>`)

	if product.Fields.Image != ConfidenceHigh {
		t.Fatalf("expected image HIGH (renditions are not a conflict), got %q reasons=%v",
			product.Fields.Image, product.Reasons)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q reasons=%v", product.Verdict, product.Reasons)
	}
}

// Regression (westelm): JSON-LD carries one Offer per size variant (68"=$799,
// 80"=$899). Consensus saw two authoritative-but-different prices and forced
// needs_review. But the page renders one selected price ($799 in the DOM), which
// disambiguates which the shopper actually pays. The displayed DOM amount must
// resolve the variant range to a confident auto-complete.
func TestEngineVariantPriceRangeDisambiguatedByDOM(t *testing.T) {
	t.Parallel()
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<script type="application/ld+json">{
			"@type":"Product","name":"Norre Console",
			"image":"https://cdn.example/norre.jpg",
			"offers":[
				{"@type":"Offer","price":"799","priceCurrency":"USD"},
				{"@type":"Offer","price":"899","priceCurrency":"USD"}
			]
		}</script>
		<meta property="og:image" content="https://cdn.example/norre.jpg">
		</head><body>
		<span class="price">$799</span>
		</body></html>`)

	if product.PriceAmount != "799" || product.PriceCurrency != "USD" {
		t.Fatalf("expected displayed 799 USD, got %q %q (reasons %v)",
			product.PriceAmount, product.PriceCurrency, product.Reasons)
	}
	if product.Fields.Price != ConfidenceHigh {
		t.Fatalf("expected price HIGH (DOM disambiguates the range), got %q reasons=%v",
			product.Fields.Price, product.Reasons)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q reasons=%v", product.Verdict, product.Reasons)
	}
}

// Guardrail: a genuine cross-source price disagreement with NO displayed DOM
// price to break the tie must still be a conflict (needs_review). This keeps the
// disambiguation from degrading the "two authoritative sources truly disagree"
// safety gate.
func TestEngineTrueAuthoritativePriceConflictStillReviews(t *testing.T) {
	t.Parallel()
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<script type="application/ld+json">{
			"@type":"Product","name":"Norre Console",
			"image":"https://cdn.example/norre.jpg",
			"offers":[
				{"@type":"Offer","price":"799","priceCurrency":"USD"},
				{"@type":"Offer","price":"899","priceCurrency":"USD"}
			]
		}</script>
		<meta property="og:image" content="https://cdn.example/norre.jpg">
		</head><body></body></html>`)

	if product.Fields.Price != ConfidenceConflict {
		t.Fatalf("expected price CONFLICT without a displayed price, got %q", product.Fields.Price)
	}
	if product.Verdict == VerdictAutoComplete {
		t.Fatalf("expected needs_review on a true price conflict, got auto_complete")
	}
}
