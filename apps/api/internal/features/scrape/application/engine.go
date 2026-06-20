package application

import (
	"net/http"
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// EngineConfig holds the tunables the consensus engine consults.
type EngineConfig struct {
	// InferDotComUSD enables the silent-wrong-price ".com → USD" inference.
	// Default OFF — prefer needs_review over a fabricated currency.
	InferDotComUSD bool
	// MaxPrice is the upper sanity bound on a scraped amount (DefaultMaxPrice
	// when <= 0).
	MaxPrice float64
}

// Engine extracts candidates from raw HTML and reconciles them into a Product
// with calibrated per-field confidence and an overall verdict. It owns no
// network or browser state, so it is fully unit-testable from HTML fixtures.
type Engine struct {
	cfg EngineConfig
}

func NewEngine(cfg EngineConfig) *Engine {
	return &Engine{cfg: cfg}
}

// Extract parses HTML once and runs every static extractor over it.
func (e *Engine) Extract(html string, finalURL string, _ http.Header) []extractors.Candidate {
	document, err := goquery.NewDocumentFromReader(strings.NewReader(html))
	if err != nil {
		return nil
	}
	base, _ := url.Parse(finalURL)

	var candidates []extractors.Candidate
	candidates = append(candidates, extractors.JSONLD(document, base)...)
	candidates = append(candidates, extractors.Microdata(document, base)...)
	candidates = append(candidates, extractors.OpenGraph(document, base)...)
	candidates = append(candidates, extractors.JSState(document, html, base)...)
	candidates = append(candidates, extractors.Merchant(document, base)...)
	candidates = append(candidates, extractors.GenericDOM(document, base)...)
	candidates = append(candidates, extractors.Links(document, base, finalURL)...)
	if inferred, ok := extractors.InferredCurrency(document, base, e.cfg.InferDotComUSD); ok {
		candidates = append(candidates, inferred)
	}
	return candidates
}

// Reconcile turns the pooled candidates into a final Product: validation gate,
// consensus per field, currency inference, then verdict. Price conversion is the
// Service's job, not the engine's.
func (e *Engine) Reconcile(candidates []extractors.Candidate, finalURL string) Product {
	host := hostOf(finalURL)

	name := resolveField(extractors.FieldName, validNameCandidates(candidates, host), nameKey)
	image := resolveField(extractors.FieldImage, validImageCandidates(candidates), exactKey)
	link := resolveField(extractors.FieldLink, candidatesOf(candidates, extractors.FieldLink), exactKey)

	price := resolvePrice(e.validPriceCandidates(candidates))
	price, currency := resolveCurrency(price, candidatesOf(candidates, extractors.FieldCurrency))

	canonical := link.value
	if canonical == "" {
		canonical = finalURL
	}

	product := Product{
		Name:          name.value,
		ImageURL:      image.value,
		PriceAmount:   price.value,
		PriceCurrency: currency.value,
		CanonicalURL:  CleanLink(canonical),
		Fields: FieldConfidences{
			Name:     name.confidence,
			Price:    price.confidence,
			Currency: currency.confidence,
			Image:    image.confidence,
			Link:     link.confidence,
		},
		CurrencyInferred: currency.inferred,
		PriceConfidence:  legacyPriceConfidence(price.confidence),
		PriceSource:      string(price.source),
		PriceRawText:     price.raw,
		PriceWarnings:    uniqueStrings(append(append([]string{}, price.warnings...), currency.warnings...)),
	}
	if currency.inferred {
		product.PriceWarnings = uniqueStrings(append(product.PriceWarnings, extractors.WarningCurrencyInferred))
	}

	product.Verdict, product.Reasons = ComputeVerdict(product)
	return product
}

func validNameCandidates(candidates []extractors.Candidate, host string) []extractors.Candidate {
	out := make([]extractors.Candidate, 0, len(candidates))
	for _, candidate := range candidates {
		if candidate.Field == extractors.FieldName && ValidateName(candidate.Value, host) {
			out = append(out, candidate)
		}
	}
	return out
}

func validImageCandidates(candidates []extractors.Candidate) []extractors.Candidate {
	out := make([]extractors.Candidate, 0, len(candidates))
	for _, candidate := range candidates {
		if candidate.Field == extractors.FieldImage && ValidateImageURL(candidate.Value) {
			out = append(out, candidate)
		}
	}
	return out
}

func (e *Engine) validPriceCandidates(candidates []extractors.Candidate) []extractors.Candidate {
	out := make([]extractors.Candidate, 0, len(candidates))
	for _, candidate := range candidates {
		if candidate.Field == extractors.FieldPrice && ValidatePrice(candidate.Value, e.cfg.MaxPrice) {
			out = append(out, candidate)
		}
	}
	return out
}

// resolvePrice reconciles already-validated price candidates by amount+currency.
// Amounts without a currency are kept (consensus + inference fill the currency).
func resolvePrice(candidates []extractors.Candidate) resolution {
	return resolveField(extractors.FieldPrice, candidates, priceKey)
}

// resolveCurrency attaches a currency to the chosen price. An explicit currency
// on the winning price source is HIGH; otherwise it falls back to the currency
// candidates (explicit page currency → HIGH, locale/TLD inference → MEDIUM).
func resolveCurrency(
	price resolution,
	currencyCandidates []extractors.Candidate,
) (resolvedPrice resolution, resolvedCurrency resolution) {
	if price.value == "" {
		return price, resolution{confidence: ConfidenceMissing}
	}
	if price.currency != "" {
		confidence := ConfidenceHigh
		if price.confidence == ConfidenceConflict {
			confidence = ConfidenceConflict
		}
		return price, resolution{value: price.currency, confidence: confidence, source: price.source}
	}

	resolved := resolveField(extractors.FieldCurrency, currencyCandidates, exactKey)
	if resolved.confidence == ConfidenceMissing {
		return price, resolution{confidence: ConfidenceMissing}
	}
	inferred := resolved.source == extractors.SourceInferred
	price.currency = resolved.value
	price.inferred = inferred
	return price, resolution{
		value:      resolved.value,
		confidence: resolved.confidence,
		source:     resolved.source,
		inferred:   inferred,
	}
}

func hostOf(rawURL string) string {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return parsed.Hostname()
}

func candidatesOf(candidates []extractors.Candidate, field extractors.Field) []extractors.Candidate {
	out := make([]extractors.Candidate, 0, len(candidates))
	for _, candidate := range candidates {
		if candidate.Field == field {
			out = append(out, candidate)
		}
	}
	return out
}

func nameKey(candidate extractors.Candidate) string {
	return strings.ToLower(strings.Join(strings.Fields(candidate.Value), " "))
}

func exactKey(candidate extractors.Candidate) string { return candidate.Value }

func priceKey(candidate extractors.Candidate) string {
	return candidate.Value + "|" + candidate.Currency
}

func legacyPriceConfidence(confidence FieldConfidence) string {
	switch confidence {
	case ConfidenceHigh:
		return PriceConfidenceHigh
	case ConfidenceMedium:
		return PriceConfidenceMedium
	case ConfidenceLow:
		return PriceConfidenceLow
	case ConfidenceConflict:
		return PriceConfidenceSuspicious
	default:
		return ""
	}
}
