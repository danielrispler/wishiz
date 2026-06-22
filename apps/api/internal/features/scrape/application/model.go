package application

type Product struct {
	Name            string   `json:"name"`
	PriceAmount     string   `json:"priceAmount"`
	PriceCurrency   string   `json:"priceCurrency"`
	ImageURL        string   `json:"imageUrl"`
	Source          string   `json:"source"`
	PriceConfidence string   `json:"priceConfidence"`
	PriceSource     string   `json:"priceSource"`
	PriceRawText    string   `json:"priceRawText"`
	PriceWarnings   []string `json:"priceWarnings"`

	// CanonicalURL is the cleaned canonical product link (rel=canonical >
	// og:url > final fetched URL, tracking params stripped). Empty until the
	// engine populates it. Downstream prefers this over the normalized URL.
	CanonicalURL string `json:"canonicalUrl,omitempty"`
	// CurrencyInferred is true when the currency was inferred (lang/locale/TLD)
	// rather than read explicitly from the price source. Caps price at MEDIUM.
	CurrencyInferred bool `json:"currencyInferred,omitempty"`
	// Fields holds per-field consensus confidence derived from cross-source
	// agreement. Empty (zero value) until the engine reconciles candidates.
	Fields FieldConfidences `json:"fields,omitzero"`
	// Verdict is the overall extraction verdict driving auto-complete vs review.
	Verdict Verdict `json:"verdict,omitempty"`
	// Reasons explains a needs_review / failed verdict for humans.
	Reasons []string `json:"reasons,omitempty"`
}

// FieldConfidence is the per-field confidence produced by the consensus engine.
// Trust is field-specific: a source authoritative for price is not necessarily
// authoritative for name (the central calibration that keeps false
// auto-completes near zero).
type FieldConfidence string

const (
	ConfidenceHigh     FieldConfidence = "high"
	ConfidenceMedium   FieldConfidence = "medium"
	ConfidenceLow      FieldConfidence = "low"
	ConfidenceConflict FieldConfidence = "conflict"
	ConfidenceMissing  FieldConfidence = "missing"
)

// FieldConfidences carries the resolved confidence for each target field.
type FieldConfidences struct {
	Name     FieldConfidence `json:"name,omitempty"`
	Price    FieldConfidence `json:"price,omitempty"`
	Currency FieldConfidence `json:"currency,omitempty"`
	Image    FieldConfidence `json:"image,omitempty"`
	Link     FieldConfidence `json:"link,omitempty"`
}

// Verdict is the overall extraction outcome.
type Verdict string

const (
	// VerdictAutoComplete: name+price at least MEDIUM (price not in conflict) and
	// currency HIGH-or-inferred-MEDIUM — safe to auto-accept without review. Image
	// is display-only and does not gate.
	VerdictAutoComplete Verdict = "auto_complete"
	// VerdictNeedsReview: enough data for a human to confirm, but not safe to
	// auto-accept.
	VerdictNeedsReview Verdict = "needs_review"
	// VerdictFailed: not enough trustworthy data to present.
	VerdictFailed Verdict = "failed"
)

func (p Product) IsComplete() bool {
	return p.Name != "" &&
		p.PriceAmount != "" &&
		p.PriceCurrency != "" &&
		p.ImageURL != ""
}

func (p Product) HasAnyData() bool {
	return p.Name != "" ||
		p.PriceAmount != "" ||
		p.PriceCurrency != "" ||
		p.ImageURL != ""
}

func (p Product) FilledFieldCount() int {
	count := 0
	if p.Name != "" {
		count++
	}
	if p.PriceAmount != "" {
		count++
	}
	if p.PriceCurrency != "" {
		count++
	}
	if p.ImageURL != "" {
		count++
	}
	return count
}

func (p Product) WithSource(source string) Product {
	p.Source = source
	return p
}

func (p Product) HasHighConfidencePrice() bool {
	return p.PriceConfidence == PriceConfidenceHigh
}

const (
	PriceConfidenceHigh       = "high"
	PriceConfidenceMedium     = "medium"
	PriceConfidenceLow        = "low"
	PriceConfidenceSuspicious = "suspicious"

	PriceSourceMerchantSelector = "merchant_selector"
	PriceSourceJSONLD           = "json_ld"
	PriceSourceMeta             = "meta"
	PriceSourceSelector         = "selector"
	PriceSourceGenericDOM       = "generic_dom"

	PriceWarningNonPrimaryContext     = "non_primary_context"
	PriceWarningConflictingCandidates = "conflicting_candidates"
	PriceWarningLowTrustSource        = "low_trust_source"
	PriceWarningMissingCurrency       = "missing_currency"
)

type PriceConverter interface {
	Convert(amount string, fromCurrency string, toCurrency string) (string, string, error)
}
