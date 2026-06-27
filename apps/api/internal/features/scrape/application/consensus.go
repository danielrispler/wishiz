package application

import (
	"sort"
	"strings"

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
		case extractors.SourceJSONLD, extractors.SourceShopify, extractors.SourceZenRowsAutoparse:
			return tierAuthoritative
		case extractors.SourceOpenGraph, extractors.SourceH1, extractors.SourceTitle,
			extractors.SourceMicrodata, extractors.SourceMerchant, extractors.SourceJSState:
			return tierDecent
		default:
			return tierWeak
		}
	case extractors.FieldPrice:
		switch source {
		case extractors.SourceJSONLD, extractors.SourceShopify, extractors.SourceOpenGraph,
			extractors.SourceZenRowsAutoparse:
			return tierAuthoritative
		case extractors.SourceMicrodata, extractors.SourceJSState, extractors.SourceMerchant:
			return tierDecent
		default:
			return tierWeak
		}
	case extractors.FieldImage:
		switch source {
		case extractors.SourceJSONLD, extractors.SourceShopify, extractors.SourceOpenGraph,
			extractors.SourceZenRowsAutoparse:
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

	// Image is a display asset: any valid product image is acceptable, so two
	// authoritative sources offering different renditions of the same photo
	// (og:image vs a JSON-LD thumbnail — near-universal) is NOT a conflict. Link
	// is likewise exempt (canonical wins outright).
	conflict := field != extractors.FieldLink &&
		field != extractors.FieldImage &&
		hasTrustedDisagreement(sorted)

	// A multi-offer JSON-LD range (one Offer per size/color variant) yields
	// several authoritative-but-different prices. The amount rendered in the
	// visible DOM tells us which variant the shopper actually sees, so a single
	// displayed price resolves the range instead of forcing needs_review.
	if conflict && field == extractors.FieldPrice {
		if disambiguated := displayedPriceWinner(sorted, candidates); disambiguated != nil {
			winner = disambiguated
			conflict = false
		}
	}

	// A name "conflict" where one value contains the other is not a contradiction:
	// it is the same product named at different verbosity (a clean <h1> vs an
	// og:title/<title> carrying a brand prefix and a "… | Site" suffix). Merge them
	// and display the clean core instead of forcing review.
	if conflict && field == extractors.FieldName {
		if merged := mergedNameWinner(sorted); merged != nil {
			winner = merged
			conflict = false
		}
	}

	confidence := confidenceFor(field, winner)
	warnings := winner.warnings
	if conflict {
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

// displayedPriceWinner resolves a price range using the amount rendered in the
// visible DOM. The "displayed" anchor is the main price the shopper sees: a
// generic-DOM price OR a host-aware Merchant price (the merchant selector reads
// the FIRST/main price element). When exactly one eligible price group's amount
// equals a displayed price, that group is what the shopper sees and wins. If no
// displayed price matches, or several do (the displayed price is itself ambiguous,
// e.g. a strikethrough was-price shown alongside the sale price), the conflict
// stands. Display prices flagged non-primary ("you may also like") are ignored so
// a carousel price can't disambiguate the wrong way.
//
// Eligibility is tier-aware: authoritative groups are always eligible (a JSON-LD
// variant range resolved by the displayed price). When NO authoritative price is
// present (e.g. Wayfair, whose price lives only in many decent RSC-flight
// primaryPrice nodes), decent groups become eligible too, so the displayed main
// price selects the right amount among the flight range.
func displayedPriceWinner(groups []*candidateGroup, candidates []extractors.Candidate) *candidateGroup {
	displayed := map[string]struct{}{}
	for _, candidate := range candidates {
		if candidate.Field != extractors.FieldPrice {
			continue
		}
		if candidate.Source != extractors.SourceGenericDOM && candidate.Source != extractors.SourceMerchant {
			continue
		}
		if hasWarning(candidate.Warnings, extractors.WarningNonPrimaryContext) {
			continue
		}
		displayed[candidate.Value] = struct{}{}
	}
	if len(displayed) == 0 {
		return nil
	}

	hasAuthoritative := false
	for _, group := range groups {
		if group.maxTier == tierAuthoritative {
			hasAuthoritative = true
			break
		}
	}

	var matches []*candidateGroup
	for _, group := range groups {
		eligible := group.maxTier == tierAuthoritative ||
			(!hasAuthoritative && group.maxTier == tierDecent)
		if !eligible {
			continue
		}
		if _, ok := displayed[group.value]; ok {
			matches = append(matches, group)
		}
	}
	if len(matches) == 0 {
		return nil
	}
	// Multiple matches are ambiguous ONLY if they disagree on the amount (e.g. a
	// strikethrough was-price shown beside the sale price). Several groups sharing
	// the SAME amount are the same price split by currency specificity (143.99 USD
	// vs a bare-$ 143.99 merchant read) — not a conflict; prefer the one carrying a
	// currency so the resolved price keeps its explicit code.
	winner := matches[0]
	for _, group := range matches[1:] {
		if group.value != winner.value {
			return nil
		}
		if winner.currency == "" && group.currency != "" {
			winner = group
		}
	}
	return winner
}

func hasWarning(warnings []string, target string) bool {
	for _, warning := range warnings {
		if warning == target {
			return true
		}
	}
	return false
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
// trust: two authoritative groups that are mutually incompatible, or — when no
// authoritative source is present — two incompatible decent groups. An
// authoritative source is never overruled (or flagged) by a merely-decent one,
// so an authoritative Shopify/JSON-LD value wins outright over a junky og:title.
func hasTrustedDisagreement(groups []*candidateGroup) bool {
	// A conflict requires ≥2 authoritative groups that genuinely contradict; one
	// authoritative group (even alongside decent ones) is never a conflict. With no
	// authoritative source, two incompatible decent groups conflict.
	return anyIncompatible(trustedConflictGroups(groups))
}

// trustedConflictGroups returns the groups that count toward a conflict: the
// authoritative ones if any exist, otherwise the decent ones. Weaker tiers never
// drive a conflict.
func trustedConflictGroups(groups []*candidateGroup) []*candidateGroup {
	var authoritative, decent []*candidateGroup
	for _, group := range groups {
		switch group.maxTier {
		case tierAuthoritative:
			authoritative = append(authoritative, group)
		case tierDecent:
			decent = append(decent, group)
		case tierNone, tierDisplay, tierWeak:
			// not trusted enough to count toward a conflict
		}
	}
	if len(authoritative) >= 1 {
		return authoritative
	}
	return decent
}

// mergedNameWinner resolves a name "conflict" that is really one product named at
// different verbosity. When every trusted name group's normalized value is a
// substring of the longest (e.g. a clean <h1> contained in an og:title that adds a
// brand prefix and a "… | Site" suffix), they describe the same product: merge
// their sources and return the cleanest (shortest) value as the winner. A value
// that is NOT contained in the longest is a genuinely different name, so the
// conflict stands (nil). The shared core must be substantial (≥3 tokens) so a
// coincidental short common token never collapses two real products together.
func mergedNameWinner(groups []*candidateGroup) *candidateGroup {
	trusted := trustedConflictGroups(groups)
	if len(trusted) < 2 {
		return nil
	}

	longest := trusted[0]
	for _, group := range trusted[1:] {
		if len(normalizeNameValue(group.value)) > len(normalizeNameValue(longest.value)) {
			longest = group
		}
	}
	longestNorm := normalizeNameValue(longest.value)

	merged := &candidateGroup{sources: map[extractors.SourceName]struct{}{}}
	shortest := trusted[0]
	for _, group := range trusted {
		if !strings.Contains(longestNorm, normalizeNameValue(group.value)) {
			return nil
		}
		for source := range group.sources {
			merged.sources[source] = struct{}{}
		}
		merged.warnings = append(merged.warnings, group.warnings...)
		if group.maxTier > merged.maxTier {
			merged.maxTier = group.maxTier
		}
		if len(normalizeNameValue(group.value)) < len(normalizeNameValue(shortest.value)) {
			shortest = group
		}
	}
	if len(strings.Fields(shortest.value)) < 3 {
		return nil
	}

	merged.value = shortest.value
	merged.currency = shortest.currency
	merged.rep = shortest.rep
	return merged
}

// normalizeNameValue lowercases and collapses whitespace so name containment
// comparisons ignore casing and the stray double-spaces sites emit.
func normalizeNameValue(value string) string {
	return strings.ToLower(strings.Join(strings.Fields(value), " "))
}

// anyIncompatible reports whether any two groups in the set genuinely contradict.
func anyIncompatible(groups []*candidateGroup) bool {
	for i := range groups {
		for j := i + 1; j < len(groups); j++ {
			if groupsIncompatible(groups[i], groups[j]) {
				return true
			}
		}
	}
	return false
}

// groupsIncompatible reports whether two candidate groups genuinely contradict.
// Different values always conflict. For prices, the same amount with two
// DIFFERENT known currencies (100 USD vs 100 EUR) conflicts, but the same amount
// where one side's currency is empty/unknown does NOT — an amount with no
// currency is less specific, not contradictory (a Shopify probe price reinforces
// the page's USD price rather than fighting it). Currency is empty for non-price
// fields, so this reduces to a value comparison for name/image/link.
func groupsIncompatible(a, b *candidateGroup) bool {
	if a.value != b.value {
		return true
	}
	return a.currency != "" && b.currency != "" && a.currency != b.currency
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
