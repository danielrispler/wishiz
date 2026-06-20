// Package extractors turns a parsed HTML page into field-level Candidates that
// the consensus engine reconciles. It is a leaf package: it imports nothing
// from the parent application package, so the engine (which produces
// application.Product) can import extractors without an import cycle.
//
// Every extractor is a pure function over a *goquery.Document (plus the base
// URL / raw HTML) and returns []Candidate. No network access except the
// Shopify probe, which lives in its own adapter.
package extractors

// Field identifies which of the five target fields a Candidate speaks to.
type Field string

const (
	FieldName     Field = "name"
	FieldPrice    Field = "price"
	FieldCurrency Field = "currency"
	FieldImage    Field = "image"
	FieldLink     Field = "link"
)

// SourceName identifies the extractor/source that produced a Candidate. Trust
// is assigned per (Field, SourceName) by the consensus trust matrix — a source
// authoritative for price is not automatically authoritative for name.
type SourceName string

const (
	SourceJSONLD     SourceName = "json_ld"
	SourceShopify    SourceName = "shopify"
	SourceOpenGraph  SourceName = "open_graph"
	SourceMicrodata  SourceName = "microdata"
	SourceJSState    SourceName = "js_state"
	SourceMerchant   SourceName = "merchant"
	SourceTitle      SourceName = "title"
	SourceH1         SourceName = "h1"
	SourceGenericDOM SourceName = "generic_dom"
	SourceCanonical  SourceName = "canonical"
	SourceFinalURL   SourceName = "final_url"
	SourceInferred   SourceName = "inferred"
)

// AllSourceNames is the single source of truth for the SourceName set written
// to product_import_jobs.price_source. The price_source CHECK constraint in
// 000001_init_wishlists.up.sql must allow exactly these values; a drift test
// (sourcenames_test.go) reads the migration SQL and diffs it against this list,
// so adding a SourceName here without widening the CHECK fails the build.
func AllSourceNames() []SourceName {
	return []SourceName{
		SourceJSONLD,
		SourceShopify,
		SourceOpenGraph,
		SourceMicrodata,
		SourceJSState,
		SourceMerchant,
		SourceTitle,
		SourceH1,
		SourceGenericDOM,
		SourceCanonical,
		SourceFinalURL,
		SourceInferred,
	}
}

// Warning constants attached to candidates / surfaced as verdict reasons.
const (
	WarningNonPrimaryContext   = "non_primary_context"
	WarningMissingCurrency     = "missing_currency"
	WarningCurrencyInferred    = "currency_inferred"
	WarningCurrencyUnconverted = "currency_unconverted"
	WarningDisplayOnlyImage    = "display_only_image"
	WarningConflict            = "conflicting_candidates"
)

// Candidate is a single extractor's vote for one field.
type Candidate struct {
	Field Field
	// Value is the normalized value: the amount for price, the ISO-4217 code
	// for currency, the absolute URL for image/link, the cleaned text for name.
	Value string
	// Currency is only set on FieldPrice candidates: the currency that
	// accompanied this amount ("" when the source gave an amount but no currency).
	Currency string
	Source   SourceName
	// Raw is the original source text, kept for debugging and PriceRawText.
	Raw string
	// Inferred marks a currency that was inferred (lang/locale/TLD) rather than
	// read explicitly from the price source. Caps the price field at MEDIUM.
	Inferred bool
	// Warnings carries source-level notes (e.g. non-primary price context).
	Warnings []string
}
