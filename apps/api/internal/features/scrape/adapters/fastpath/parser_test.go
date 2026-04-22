package fastpath

import (
	"testing"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

func TestExtractProductZaraSelectors(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://www.zara.com/il/he/product",
		`<html><body><h1>שמלת מיני קולר פרחונית</h1><span class="price__amount">169.90 ₪</span><div data-qa-action="product-slide"><img src="https://static.zara.net/image.jpg"></div></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}

	if product.Name != "שמלת מיני קולר פרחונית" || product.PriceAmount != "169.90" || product.PriceCurrency != "ILS" || product.ImageURL != "https://static.zara.net/image.jpg" {
		t.Fatalf("unexpected product: %+v", product)
	}
	if product.PriceConfidence != scrapeapp.PriceConfidenceHigh || product.PriceSource != scrapeapp.PriceSourceMerchantSelector {
		t.Fatalf("unexpected price metadata: %+v", product)
	}
}

func TestExtractProductUniqloSelectors(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://www.uniqlo.com/us/en/products/item",
		`<html><body><h1>AIRism Cotton Oversized T-Shirt | Half-Sleeve</h1><div class="price-box">$19.90</div><picture><source srcset="https://image.uniqlo.com/hero.jpg 1x"></picture></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}

	if product.Name != "AIRism Cotton Oversized T-Shirt | Half-Sleeve" || product.PriceAmount != "19.90" || product.PriceCurrency != "USD" || product.ImageURL != "https://image.uniqlo.com/hero.jpg" {
		t.Fatalf("unexpected product: %+v", product)
	}
}

func TestExtractProductJSONLDPriceIsHighConfidence(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://shop.example/products/lamp",
		`<html><head><script type="application/ld+json">{
			"@type": "Product",
			"name": "Desk lamp",
			"image": "https://shop.example/lamp.png",
			"offers": {"@type": "Offer", "price": "40.00", "priceCurrency": "USD"}
		}</script></head><body></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}
	if product.PriceAmount != "40.00" || product.PriceCurrency != "USD" {
		t.Fatalf("unexpected price: %+v", product)
	}
	if product.PriceConfidence != scrapeapp.PriceConfidenceHigh || product.PriceSource != scrapeapp.PriceSourceJSONLD {
		t.Fatalf("unexpected price metadata: %+v", product)
	}
}

func TestExtractProductCurrentPriceIsMediumConfidence(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://shop.example/products/lamp",
		`<html><body><h1>Desk lamp</h1><div class="current-price">$40.00</div><img src="/lamp.png"></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}
	if product.PriceAmount != "40.00" || product.PriceConfidence != scrapeapp.PriceConfidenceMedium {
		t.Fatalf("unexpected product: %+v", product)
	}
}

func TestExtractProductNonPrimaryPriceIsSuspicious(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://shop.example/products/lamp",
		`<html><body><h1>Desk lamp</h1><div class="current-price installment">$10.00 per month</div><img src="/lamp.png"></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}
	if product.PriceConfidence != scrapeapp.PriceConfidenceSuspicious {
		t.Fatalf("expected suspicious price, got %+v", product)
	}
	if !contains(product.PriceWarnings, scrapeapp.PriceWarningNonPrimaryContext) {
		t.Fatalf("expected non-primary warning, got %+v", product.PriceWarnings)
	}
}

func TestExtractProductConflictingTrustedPricesAreSuspicious(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://shop.example/products/lamp",
		`<html><head>
			<meta property="product:price:amount" content="40.00">
			<meta property="product:price:currency" content="USD">
		</head><body><h1>Desk lamp</h1><div class="current-price">$35.00</div><img src="/lamp.png"></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}
	if product.PriceConfidence != scrapeapp.PriceConfidenceSuspicious {
		t.Fatalf("expected suspicious conflict, got %+v", product)
	}
	if !contains(product.PriceWarnings, scrapeapp.PriceWarningConflictingCandidates) {
		t.Fatalf("expected conflict warning, got %+v", product.PriceWarnings)
	}
}

func TestExtractProductMissingCurrencyIsNotTrusted(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://shop.example/products/lamp",
		`<html><body><h1>Desk lamp</h1><div class="current-price">40.00</div><img src="/lamp.png"></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}
	if product.PriceAmount != "" || product.PriceConfidence != "" {
		t.Fatalf("expected missing-currency price to be discarded, got %+v", product)
	}
}

func contains(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func TestExtractProductHMSelectors(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://www2.hm.com/hw_il/productpage.1311897004.html",
		`<html><head><meta property="og:title" content="חולצת פולו מכותנה Loose Fit"></head><body><h1>חולצת פולו מכותנה Loose Fit</h1><div data-testid="formatted-value">199.00 ₪</div><picture><source srcset="https://image.hm.com/assets/hm/fe/27/fe2764943b4b1b022bb238eaf0279ce189efd7b6.jpg?imwidth=2160 1x"></picture></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}

	if product.Name != "חולצת פולו מכותנה Loose Fit" || product.PriceAmount != "199.00" || product.PriceCurrency != "ILS" || product.ImageURL != "https://image.hm.com/assets/hm/fe/27/fe2764943b4b1b022bb238eaf0279ce189efd7b6.jpg?imwidth=2160" {
		t.Fatalf("unexpected product: %+v", product)
	}
}

func TestExtractProductNikeSelectors(t *testing.T) {
	t.Parallel()

	product, err := ExtractProduct(
		"https://www.nike.com/il/product",
		`<html><body><h1 id="pdp_product_title">Nike Shox TL</h1><div data-test="product-price">₪ 599.90</div><div data-test="hero-image"><img src="https://static.nike.com/hero.png"></div></body></html>`,
	)
	if err != nil {
		t.Fatalf("extract product: %v", err)
	}

	if product.Name != "Nike Shox TL" || product.PriceAmount != "599.90" || product.PriceCurrency != "ILS" || product.ImageURL != "https://static.nike.com/hero.png" {
		t.Fatalf("unexpected product: %+v", product)
	}
}
