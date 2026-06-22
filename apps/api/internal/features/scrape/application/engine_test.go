package application

import (
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

func reconcile(t *testing.T, finalURL, html string) Product {
	t.Helper()
	engine := NewEngine(EngineConfig{})
	return engine.Reconcile(engine.Extract(html, finalURL, nil), finalURL)
}

func TestEngineJSONLDProductAutoCompletes(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/products/lamp", `<html><head>
		<script type="application/ld+json">{
			"@type": "Product",
			"name": "Desk lamp",
			"image": "https://shop.example/lamp.png",
			"offers": {"@type": "Offer", "price": "40.00", "priceCurrency": "USD"}
		}</script></head><body></body></html>`)

	if product.Name != "Desk lamp" || product.PriceAmount != "40.00" || product.PriceCurrency != "USD" {
		t.Fatalf("unexpected product: %+v", product)
	}
	if product.ImageURL != "https://shop.example/lamp.png" {
		t.Fatalf("unexpected image: %q", product.ImageURL)
	}
	if product.Fields.Name != ConfidenceHigh || product.Fields.Image != ConfidenceHigh ||
		product.Fields.Price != ConfidenceHigh || product.Fields.Currency != ConfidenceHigh {
		t.Fatalf("expected all-high confidence, got %+v", product.Fields)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
}

func TestEngineJSONLDNumericPrice(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://vuoriclothing.com/products/bra", `<html><head>
		<script type="application/ld+json">{
			"@type": "Product", "name": "Vuori Bra", "image": "https://x/bra.png",
			"offers": {"@type": "Offer", "price": 128, "priceCurrency": "USD"}
		}</script></head><body></body></html>`)

	if product.PriceAmount != "128" || product.PriceCurrency != "USD" {
		t.Fatalf("unexpected price: %+v", product)
	}
}

func TestEngineLoneOgTitleMediumNameAutoCompletes(t *testing.T) {
	t.Parallel()

	// A lone og:title yields a MEDIUM name. With the relaxed gate (MEDIUM name
	// accepted) plus HIGH og:image/price/currency, the product auto-completes.
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<meta property="og:title" content="Brand | Cool Lamp">
		<meta property="og:image" content="https://x/lamp.png">
		<meta property="product:price:amount" content="40">
		<meta property="product:price:currency" content="USD">
		</head><body></body></html>`)

	if product.Fields.Name != ConfidenceMedium {
		t.Fatalf("expected lone og:title -> MEDIUM name, got %q", product.Fields.Name)
	}
	if product.Fields.Image != ConfidenceHigh || product.Fields.Price != ConfidenceHigh {
		t.Fatalf("expected og:image/price HIGH, got %+v", product.Fields)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete with MEDIUM name, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
}

func TestEngineCorroboratedNameIsHigh(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/p", `<html><head>
		<title>Cool Lamp</title>
		<meta property="og:title" content="Cool Lamp">
		<meta property="og:image" content="https://x/lamp.png">
		<meta property="product:price:amount" content="40">
		<meta property="product:price:currency" content="USD">
		</head><body><h1>Cool Lamp</h1></body></html>`)

	if product.Fields.Name != ConfidenceHigh {
		t.Fatalf("expected corroborated name HIGH, got %q", product.Fields.Name)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
}

func TestEngineDOMOnlyPriceIsLowNotAutoComplete(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/p", `<html><head>
		<title>Lamp</title><meta property="og:title" content="Lamp">
		<meta property="og:image" content="https://x/lamp.png"></head>
		<body><h1>Lamp</h1><div class="current-price">$40.00</div></body></html>`)

	if product.PriceAmount != "40.00" || product.Fields.Price != ConfidenceLow {
		t.Fatalf("expected DOM price LOW, got amount=%q conf=%q", product.PriceAmount, product.Fields.Price)
	}
	if product.Verdict != VerdictNeedsReview {
		t.Fatalf("expected needs_review, got %q", product.Verdict)
	}
}

func TestEngineMissingCurrencyKeepsAmountButCurrencyMissing(t *testing.T) {
	t.Parallel()

	// .com host gives no locale/TLD inference, so the amount is recovered (LOW)
	// but the currency stays MISSING — honest needs_review, not a fabricated USD.
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<meta property="og:title" content="Lamp"><meta property="og:image" content="https://x/lamp.png">
		</head><body><h1>Lamp</h1><div class="current-price">40.00</div></body></html>`)

	if product.PriceAmount != "40.00" || product.Fields.Price != ConfidenceLow {
		t.Fatalf("expected amount kept LOW, got amount=%q conf=%q", product.PriceAmount, product.Fields.Price)
	}
	if product.PriceCurrency != "" || product.Fields.Currency != ConfidenceMissing {
		t.Fatalf("expected currency MISSING, got %q/%q", product.PriceCurrency, product.Fields.Currency)
	}
	if product.Verdict == VerdictAutoComplete {
		t.Fatalf("missing currency must not auto_complete")
	}
}

func TestEngineCurrencyInferenceFromTLD(t *testing.T) {
	t.Parallel()

	// A .co.il store with an authoritative JSON-LD price/name/image but no
	// currency: TLD inference supplies ILS (MEDIUM) and the product auto-completes.
	product := reconcile(t, "https://shop.co.il/products/lamp", `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Lamp","image":"https://x/lamp.png",
			"offers":{"@type":"Offer","price":"199"}}</script></head><body></body></html>`)

	if product.PriceCurrency != "ILS" || !product.CurrencyInferred {
		t.Fatalf("expected inferred ILS, got %q inferred=%v", product.PriceCurrency, product.CurrencyInferred)
	}
	if product.Fields.Currency != ConfidenceMedium {
		t.Fatalf("expected inferred currency MEDIUM, got %q", product.Fields.Currency)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete with inferred currency, got %q (%v)", product.Verdict, product.Reasons)
	}
	if !containsStr(product.PriceWarnings, "currency_inferred") {
		t.Fatalf("expected currency_inferred warning, got %v", product.PriceWarnings)
	}
}

func TestEngineRejectsAntiBotName(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/p", `<html><head>
		<title>Just a moment...</title><meta property="og:title" content="Just a moment...">
		</head><body><h1>Attention Required! | Cloudflare</h1></body></html>`)

	if product.Name != "" || product.Fields.Name != ConfidenceMissing {
		t.Fatalf("expected anti-bot name rejected, got %q/%q", product.Name, product.Fields.Name)
	}
}

func TestEngineRejectsLogoImageAndStripsTracking(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/p?utm_source=google&gclid=abc&id=5", `<html><head>
		<link rel="canonical" href="https://shop.example/p?utm_source=google&id=5">
		<script type="application/ld+json">{"@type":"Product","name":"Lamp",
			"image":"https://x/brand-logo.svg","offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		</head><body></body></html>`)

	if product.ImageURL != "" || product.Fields.Image != ConfidenceMissing {
		t.Fatalf("expected logo image rejected, got %q/%q", product.ImageURL, product.Fields.Image)
	}
	if product.CanonicalURL != "https://shop.example/p?id=5" {
		t.Fatalf("expected tracking params stripped, got %q", product.CanonicalURL)
	}
}

func TestEngineRejectsAbsurdPrice(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/p", `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Lamp","image":"https://x/lamp.png",
			"offers":{"@type":"Offer","price":"99999999","priceCurrency":"USD"}}</script></head><body></body></html>`)

	if product.PriceAmount != "" || product.Fields.Price != ConfidenceMissing {
		t.Fatalf("expected absurd price rejected, got %q/%q", product.PriceAmount, product.Fields.Price)
	}
}

func TestEngineConflictingTrustedPricesAreConflict(t *testing.T) {
	t.Parallel()

	product := reconcile(t, "https://shop.example/p", `<html><head>
		<meta property="og:title" content="Lamp"><meta property="og:image" content="https://x/lamp.png">
		<meta property="product:price:amount" content="35"><meta property="product:price:currency" content="USD">
		<script type="application/ld+json">{"@type":"Product","name":"Lamp",
			"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		</head><body><h1>Lamp</h1></body></html>`)

	if product.Fields.Price != ConfidenceConflict {
		t.Fatalf("expected price CONFLICT, got %q", product.Fields.Price)
	}
	if !containsStr(product.PriceWarnings, "conflicting_candidates") {
		t.Fatalf("expected conflict warning, got %v", product.PriceWarnings)
	}
	if product.Verdict == VerdictAutoComplete {
		t.Fatalf("conflict must not auto_complete")
	}
}

func TestEngineJSONLDIgnoresRecommendationProducts(t *testing.T) {
	t.Parallel()

	// A page with a primary product plus a recommendation-carousel product (both
	// Product JSON-LD with offers) must NOT create a false price conflict: only
	// the primary product (matching the canonical URL) contributes candidates.
	finalURL := "https://shop.example/products/lamp"
	product := reconcile(t, finalURL, `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Desk Lamp",
			"url":"https://shop.example/products/lamp","image":"https://x/lamp.png",
			"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		<script type="application/ld+json">{"@type":"Product","name":"Other Lamp",
			"image":"https://x/other.png",
			"offers":{"@type":"Offer","price":"999","priceCurrency":"USD"}}</script>
		</head><body></body></html>`)

	if product.Fields.Price == ConfidenceConflict {
		t.Fatalf("recommendation product must not create a price conflict")
	}
	if product.PriceAmount != "40" {
		t.Fatalf("expected the primary product price 40, got %q", product.PriceAmount)
	}
}

func TestEngineSameAmountDifferentCurrencyIsConflict(t *testing.T) {
	t.Parallel()

	// Two authoritative price sources agree on the amount but disagree on the
	// currency (100 USD vs 100 EUR). That is a real conflict — picking either is
	// a silent-wrong-price — so it must drop to CONFLICT, not auto-complete.
	engine := NewEngine(EngineConfig{})
	finalURL := "https://store.example/products/tee"
	candidates := []extractors.Candidate{
		{Field: extractors.FieldName, Value: "Tee", Source: extractors.SourceShopify},
		{Field: extractors.FieldImage, Value: "https://cdn/tee.jpg", Source: extractors.SourceShopify},
		{Field: extractors.FieldPrice, Value: "100", Currency: "USD", Source: extractors.SourceJSONLD},
		{Field: extractors.FieldPrice, Value: "100", Currency: "EUR", Source: extractors.SourceShopify},
	}

	product := engine.Reconcile(candidates, finalURL)
	if product.Fields.Price != ConfidenceConflict {
		t.Fatalf("same amount, conflicting currency must be CONFLICT, got %q (currency %q)",
			product.Fields.Price, product.PriceCurrency)
	}
	if product.Verdict == VerdictAutoComplete {
		t.Fatalf("currency conflict must not auto_complete")
	}
}

func TestEngineDOMOnlyImageStillAutoCompletes(t *testing.T) {
	t.Parallel()

	// Image is display-only and no longer gates the verdict. JSON-LD gives HIGH
	// name/price/currency; the only image is a DOM <img> (LOW). The product
	// auto-completes and still surfaces the LOW image for display.
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Lamp",
			"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		</head><body><img src="https://x/lamp.png"></body></html>`)

	if product.ImageURL != "https://x/lamp.png" || product.Fields.Image != ConfidenceLow {
		t.Fatalf("expected DOM image LOW, got url=%q conf=%q", product.ImageURL, product.Fields.Image)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("display-only image must not block auto_complete, got %q (%v)", product.Verdict, product.Reasons)
	}
}

func TestEngineShopifyCandidatesAutoComplete(t *testing.T) {
	t.Parallel()

	engine := NewEngine(EngineConfig{})
	finalURL := "https://store.example/products/tee"
	candidates := engine.Extract(`<html><head><meta property="og:title" content="Tee"></head><body></body></html>`, finalURL, nil)
	candidates = append(candidates,
		extractors.Candidate{Field: extractors.FieldName, Value: "Cotton Tee", Source: extractors.SourceShopify},
		extractors.Candidate{Field: extractors.FieldImage, Value: "https://cdn/tee.jpg", Source: extractors.SourceShopify},
		extractors.NewShopifyPriceCandidate("25.00", "USD"),
	)

	product := engine.Reconcile(candidates, finalURL)
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("expected auto_complete from Shopify, got %q (reasons %v)", product.Verdict, product.Reasons)
	}
	if product.Name != "Cotton Tee" || product.PriceAmount != "25.00" || product.PriceCurrency != "USD" {
		t.Fatalf("unexpected product: %+v", product)
	}
}

func TestEngineMerchantPriceMediumCurrencyMissingReviews(t *testing.T) {
	t.Parallel()

	// JSON-LD gives HIGH name+image; the merchant selector supplies a MEDIUM
	// price. The MEDIUM price is now accepted, but the bare "$" on a .com yields
	// NO currency (SAFE policy), so the missing currency — not the price — is what
	// holds it in needs_review.
	product := reconcile(t, "https://vuoriclothing.com/products/villa", `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Villa Pant","image":"https://x/villa.png"}</script>
		</head><body><span data-testid="productdescriptionprice-price">$128</span></body></html>`)

	if product.PriceAmount != "128" || product.Fields.Price != ConfidenceMedium {
		t.Fatalf("expected merchant price MEDIUM, got amount=%q conf=%q", product.PriceAmount, product.Fields.Price)
	}
	if product.Fields.Currency != ConfidenceMissing {
		t.Fatalf("expected currency MISSING (bare $ on .com), got %q", product.Fields.Currency)
	}
	if product.Verdict != VerdictNeedsReview {
		t.Fatalf("missing currency must hold needs_review, got %q (%v)", product.Verdict, product.Reasons)
	}
}

func TestEngineMicrodataAloneAutoCompletes(t *testing.T) {
	t.Parallel()

	// Microdata is a single MEDIUM source for price/image, with an explicit USD
	// currency (HIGH). The relaxed gate accepts a single-source MEDIUM name+price,
	// so this now auto-completes.
	product := reconcile(t, "https://shop.example/p", `<html><body>
		<div itemscope itemtype="http://schema.org/Product">
			<span itemprop="name">Wool Scarf</span>
			<img itemprop="image" src="https://x/scarf.png">
			<span itemprop="price" content="49.99">49.99</span>
			<meta itemprop="priceCurrency" content="USD">
		</div></body></html>`)

	if product.PriceAmount != "49.99" || product.PriceCurrency != "USD" {
		t.Fatalf("unexpected microdata product: %+v", product)
	}
	if product.Fields.Price != ConfidenceMedium {
		t.Fatalf("expected single-source microdata price MEDIUM, got %q", product.Fields.Price)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("single-source MEDIUM price must auto_complete, got %q (%v)", product.Verdict, product.Reasons)
	}
}

func TestEngineImageMissingAutoCompletes(t *testing.T) {
	t.Parallel()

	// No image at all: image is optional for the verdict, so HIGH name/price/
	// currency still auto-completes with an empty ImageURL.
	product := reconcile(t, "https://shop.example/products/lamp", `<html><head>
		<script type="application/ld+json">{"@type":"Product","name":"Desk Lamp",
			"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		</head><body></body></html>`)

	if product.ImageURL != "" || product.Fields.Image != ConfidenceMissing {
		t.Fatalf("expected no image, got url=%q conf=%q", product.ImageURL, product.Fields.Image)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("missing image must not block auto_complete, got %q (%v)", product.Verdict, product.Reasons)
	}
}

func TestEngineBrandImageFallbackWhenNoProductImage(t *testing.T) {
	t.Parallel()

	// No product image survives, but the page exposes an apple-touch-icon. The
	// engine fills ImageURL with that brand asset (display-only) + a warning, and
	// still auto-completes off the HIGH name/price/currency.
	product := reconcile(t, "https://shop.example/products/lamp", `<html><head>
		<link rel="apple-touch-icon" href="/brand-touch.png">
		<script type="application/ld+json">{"@type":"Product","name":"Desk Lamp",
			"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		</head><body></body></html>`)

	if product.ImageURL != "https://shop.example/brand-touch.png" {
		t.Fatalf("expected brand-image fallback, got %q", product.ImageURL)
	}
	if !containsStr(product.PriceWarnings, extractors.WarningBrandImageFallback) {
		t.Fatalf("expected brand-image fallback warning, got %v", product.PriceWarnings)
	}
	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("brand fallback must not block auto_complete, got %q (%v)", product.Verdict, product.Reasons)
	}
}

func TestEngineProductImageBeatsBrandFallback(t *testing.T) {
	t.Parallel()

	// When a real product image exists, the brand asset (apple-touch-icon) is
	// ignored: the product image wins and no fallback warning is added.
	product := reconcile(t, "https://shop.example/products/lamp", `<html><head>
		<link rel="apple-touch-icon" href="/brand-touch.png">
		<script type="application/ld+json">{"@type":"Product","name":"Desk Lamp","image":"https://x/lamp.png",
			"offers":{"@type":"Offer","price":"40","priceCurrency":"USD"}}</script>
		</head><body></body></html>`)

	if product.ImageURL != "https://x/lamp.png" {
		t.Fatalf("expected product image to win, got %q", product.ImageURL)
	}
	if containsStr(product.PriceWarnings, extractors.WarningBrandImageFallback) {
		t.Fatalf("brand fallback must not fire when a product image exists: %v", product.PriceWarnings)
	}
}

func TestEngineBrandImageSkippedOnFailedVerdict(t *testing.T) {
	t.Parallel()

	// A pure block page (anti-bot name rejected, no price) fails. The brand asset
	// must NOT be attached to a failed scrape — a failed product shows nothing.
	product := reconcile(t, "https://shop.example/p", `<html><head>
		<link rel="apple-touch-icon" href="/brand-touch.png">
		<title>Just a moment...</title></head>
		<body><h1>Attention Required! | Cloudflare</h1></body></html>`)

	if product.Verdict != VerdictFailed {
		t.Fatalf("expected failed verdict, got %q", product.Verdict)
	}
	if product.ImageURL != "" {
		t.Fatalf("failed scrape must not carry a brand image, got %q", product.ImageURL)
	}
}

func containsStr(values []string, want string) bool {
	for _, v := range values {
		if v == want {
			return true
		}
	}
	return false
}
