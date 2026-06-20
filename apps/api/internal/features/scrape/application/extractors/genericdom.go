package extractors

import (
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// genericPriceSelectors are common price containers, tried as a last resort.
// Everything here is LOW trust (display-only / never an auto-complete basis).
var genericPriceSelectors = []string{
	`[itemprop="price"]`,
	".current-price",
	".sale-price",
	".price-current",
	".price__current",
	".price-amount",
	".price__amount",
	".price",
	".product-price",
}

// GenericDOM is the lowest-trust fallback: a first product-ish <img> and any
// price-shaped text it can find. Used only to corroborate or to give a human
// something to review — never to auto-complete.
func GenericDOM(document *goquery.Document, base *url.URL) []Candidate {
	var candidates []Candidate

	if image := firstSource(document, "img", "src", "srcset", "data-src"); image != "" {
		candidates = append(candidates, Candidate{
			Field: FieldImage, Value: resolveURL(base, image), Source: SourceGenericDOM, Raw: image,
		})
	}

	for _, selector := range genericPriceSelectors {
		document.Find(selector).Each(func(_ int, selection *goquery.Selection) {
			raw := firstNonEmpty(
				attributeValue(selection, "content"),
				attributeValue(selection, "data-price"),
				attributeValue(selection, "aria-label"),
				selection.Text(),
			)
			if raw == "" {
				return
			}
			candidate, ok := newPriceCandidate(SourceGenericDOM, "", raw)
			if !ok {
				return
			}
			context := normalizeText(strings.Join([]string{
				attributeValue(selection, "class"),
				attributeValue(selection, "id"),
				raw,
			}, " "))
			if looksLikeNonPrimaryPrice(context) {
				candidate.Warnings = append(candidate.Warnings, WarningNonPrimaryContext)
			}
			candidates = append(candidates, candidate)
		})
	}

	return candidates
}

func attributeValue(selection *goquery.Selection, name string) string {
	value, _ := selection.Attr(name)
	return value
}
