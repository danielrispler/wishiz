package application

import "context"

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
}

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

type Scraper interface {
	Scrape(ctx context.Context, rawURL string) (Product, error)
}

type PriceConverter interface {
	Convert(amount string, fromCurrency string, toCurrency string) (string, string, error)
}
