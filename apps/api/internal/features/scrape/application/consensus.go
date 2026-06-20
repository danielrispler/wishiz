package application

import (
	"sort"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// trustTier is how much a source can be trusted for a particular field. Trust
// is field-specific: the same source can be authoritative for price yet only
// display-quality for image.
type trustTier int

const (
	tierNone          trustTier = iota
	tierDisplay                 // image only: safe to show, never an auto-complete basis
	tierWeak                    // LOW — generic DOM / final URL
	tierDecent                  // MEDIUM alone, HIGH when ≥2 distinct decent sources agree
	tierAuthoritative           // HIGH alone
)

// trustFor is the consensus trust matrix. This is the central calibration that
// keeps false auto-completes near zero.
func trustFor(field extractors.Field, source extractors.SourceName) trustTier {
	switch field {
	case extractors.FieldName:
		switch source {
		case extractors.SourceJSONLD, extractors.SourceShopify:
			return tierAuthoritative
		case extractors.SourceOpenGraph, extractors.SourceH1, extractors.SourceTitle,
			extractors.SourceMicrodata, extractors.SourceMerchant, extractors.SourceJSState:
			return tierDecent
		default:
			return tierWeak
		}
	case extractors.FieldPrice:
		switch source {
		case extractors.SourceJSONLD, extractors.SourceShopify, extractors.SourceOpenGraph:
			return tierAuthoritative
		case extractors.SourceMicrodata, extractors.SourceJSState, extractors.SourceMerchant:
			return tierDecent
		default:
			return tierWeak
		}
	case extractors.FieldImage:
		switch source {
		case extractors.SourceJSONLD, extractors.SourceShopify, extractors.SourceOpenGraph:
			return tierAuthoritative
		case extractors.SourceMicrodata:
			return tierDecent
		default:
			return tierDisplay
		}
	case extractors.FieldLink:
		switch source {
		case extractors.SourceCanonical:
			return tierAuthoritative
		case extractors.SourceOpenGraph:
			return tierDecent
		default:
			return tierWeak
		}
	case extractors.FieldCurrency:
		if source == extractors.SourceInferred {
			return tierDecent
		}
		return tierAuthoritative
	}
	return tierNone
}

// resolution is the consensus outcome for a single field.
type resolution struct {
	value      string
	currency   string // FieldPrice only: the currency that travels with the amount
	confidence FieldConfidence
	source     extractors.SourceName
	raw        string
	inferred   bool
	warnings   []string
}

type candidateGroup struct {
	value    string
	currency string
	maxTier  trustTier
	rep      extractors.Candidate
	sources  map[extractors.SourceName]struct{}
	warnings []string
}

// resolveField groups candidates by keyFn and derives a confidence from
// cross-source agreement and the trust matrix.
func resolveField(
	field extractors.Field,
	candidates []extractors.Candidate,
	keyFn func(extractors.Candidate) string,
) resolution {
	groups := map[string]*candidateGroup{}
	order := []string{}

	for _, candidate := range candidates {
		if candidate.Value == "" {
			continue
		}
		tier := trustFor(field, candidate.Source)
		if tier == tierNone {
			continue
		}
		key := keyFn(candidate)
		group, ok := groups[key]
		if !ok {
			group = &candidateGroup{
				value:    candidate.Value,
				currency: candidate.Currency,
				sources:  map[extractors.SourceName]struct{}{},
			}
			groups[key] = group
			order = append(order, key)
		}
		group.sources[candidate.Source] = struct{}{}
		group.warnings = append(group.warnings, candidate.Warnings...)
		if tier > group.maxTier {
			group.maxTier = tier
			group.rep = candidate
			group.value = candidate.Value
			group.currency = candidate.Currency
		}
	}

	if len(groups) == 0 {
		return resolution{confidence: ConfidenceMissing}
	}

	sorted := make([]*candidateGroup, 0, len(groups))
	for _, key := range order {
		sorted = append(sorted, groups[key])
	}
	sort.SliceStable(sorted, func(i, j int) bool {
		if sorted[i].maxTier != sorted[j].maxTier {
			return sorted[i].maxTier > sorted[j].maxTier
		}
		di, dj := decentSourceCount(field, sorted[i]), decentSourceCount(field, sorted[j])
		if di != dj {
			return di > dj
		}
		return sorted[i].value < sorted[j].value
	})

	winner := sorted[0]
	confidence := confidenceFor(field, winner)
	warnings := winner.warnings

	if field != extractors.FieldLink && hasTrustedDisagreement(sorted) {
		confidence = ConfidenceConflict
		warnings = append(warnings, extractors.WarningConflict)
	}

	return resolution{
		value:      winner.value,
		currency:   winner.currency,
		confidence: confidence,
		source:     winner.rep.Source,
		raw:        winner.rep.Raw,
		inferred:   winner.rep.Inferred,
		warnings:   uniqueStrings(warnings),
	}
}

func confidenceFor(field extractors.Field, group *candidateGroup) FieldConfidence {
	if field == extractors.FieldImage && group.maxTier <= tierDisplay {
		return ConfidenceLow
	}
	switch group.maxTier {
	case tierAuthoritative:
		return ConfidenceHigh
	case tierDecent:
		if decentSourceCount(field, group) >= 2 {
			return ConfidenceHigh
		}
		return ConfidenceMedium
	case tierWeak, tierDisplay:
		return ConfidenceLow
	default:
		return ConfidenceMissing
	}
}

func decentSourceCount(field extractors.Field, group *candidateGroup) int {
	count := 0
	for source := range group.sources {
		if trustFor(field, source) >= tierDecent {
			count++
		}
	}
	return count
}

// hasTrustedDisagreement reports a conflict only between sources of comparable
// trust: ≥2 authoritative groups with different values, or — when no
// authoritative source is present — ≥2 decent groups that disagree. An
// authoritative source is never overruled (or flagged) by a merely-decent one,
// so an authoritative Shopify/JSON-LD value wins outright over a junky og:title.
func hasTrustedDisagreement(groups []*candidateGroup) bool {
	authoritative := map[string]struct{}{}
	decent := map[string]struct{}{}
	for _, group := range groups {
		key := disagreementKey(group)
		switch group.maxTier {
		case tierAuthoritative:
			authoritative[key] = struct{}{}
		case tierDecent:
			decent[key] = struct{}{}
		case tierNone, tierDisplay, tierWeak:
			// not trusted enough to count toward a conflict
		}
	}
	if len(authoritative) >= 2 {
		return true
	}
	if len(authoritative) == 1 {
		return false
	}
	return len(decent) >= 2
}

// disagreementKey combines amount and currency so that two price groups with the
// same amount but different currency (100 USD vs 100 EUR) count as a conflict.
// Currency is empty for non-price fields, so this is a no-op for name/image/link.
func disagreementKey(group *candidateGroup) string {
	return group.value + "\x00" + group.currency
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	result := make([]string, 0, len(values))
	for _, value := range values {
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		result = append(result, value)
	}
	return result
}
