package application

import (
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// Autoparse candidates are authoritative for name/price/image: a single
// zenrows_autoparse name + price (with an explicit marketplace currency) must
// reconcile to auto_complete, mirroring JSON-LD/Shopify.
func TestReconcileAutoparseCandidatesAutoComplete(t *testing.T) {
	t.Parallel()

	candidates := []extractors.Candidate{
		{Field: extractors.FieldName, Value: "Redken Shampoo", Source: extractors.SourceZenRowsAutoparse},
		{Field: extractors.FieldImage, Value: "https://m.media-amazon.com/i.jpg", Source: extractors.SourceZenRowsAutoparse},
		{Field: extractors.FieldPrice, Value: "23.80", Currency: "USD", Source: extractors.SourceZenRowsAutoparse},
	}

	product := NewEngine(EngineConfig{}).Reconcile(candidates, "https://www.amazon.com/dp/B0B64RSCCV")

	if product.Verdict != VerdictAutoComplete {
		t.Fatalf("verdict = %q, want auto_complete (reasons: %v)", product.Verdict, product.Reasons)
	}
	if product.PriceAmount != "23.80" || product.PriceCurrency != "USD" {
		t.Fatalf("price = {%q %q}, want {23.80 USD}", product.PriceAmount, product.PriceCurrency)
	}
	if product.PriceSource != string(extractors.SourceZenRowsAutoparse) {
		t.Fatalf("price source = %q, want zenrows_autoparse", product.PriceSource)
	}
}
