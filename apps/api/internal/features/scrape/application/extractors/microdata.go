package extractors

import (
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// Microdata extracts candidates from schema.org Product microdata
// ([itemtype*="schema.org/Product"] with [itemprop=name|price|priceCurrency|image]).
// A decent (corroborating) structured source.
func Microdata(document *goquery.Document, base *url.URL) []Candidate {
	var candidates []Candidate

	document.Find(`[itemtype*="schema.org/Product"]`).Each(func(_ int, scope *goquery.Selection) {
		name := normalizeText(itemprop(scope, "name"))
		if name != "" {
			candidates = append(candidates, Candidate{Field: FieldName, Value: name, Source: SourceMicrodata, Raw: name})
		}

		if image := firstItempropSource(scope, "image"); image != "" {
			candidates = append(candidates, Candidate{
				Field: FieldImage, Value: resolveURL(base, image), Source: SourceMicrodata, Raw: image,
			})
		}

		amount := normalizeText(itemprop(scope, "price"))
		currency := normalizeText(itemprop(scope, "priceCurrency"))
		if amount != "" {
			if candidate, ok := newPriceCandidate(SourceMicrodata, currency, joinPrice(currency, amount)); ok {
				candidates = append(candidates, candidate)
			}
		}
		if currency != "" {
			candidates = append(candidates, Candidate{
				Field: FieldCurrency, Value: strings.ToUpper(currency), Source: SourceMicrodata, Raw: currency,
			})
		}
	})

	return candidates
}

// itemprop returns the value of a microdata property: the content/value
// attribute when present (meta/link/data elements), else the element text.
func itemprop(scope *goquery.Selection, prop string) string {
	selection := scope.Find(`[itemprop="` + prop + `"]`).First()
	if selection.Length() == 0 {
		return ""
	}
	for _, attr := range []string{"content", "value"} {
		if value, ok := selection.Attr(attr); ok && strings.TrimSpace(value) != "" {
			return value
		}
	}
	return selection.Text()
}

func firstItempropSource(scope *goquery.Selection, prop string) string {
	selection := scope.Find(`[itemprop="` + prop + `"]`).First()
	if selection.Length() == 0 {
		return ""
	}
	for _, attr := range []string{"content", "src", "href"} {
		if value, ok := selection.Attr(attr); ok {
			if candidate := parseSourceValue(value); candidate != "" && !looksLikeNonProductImage(candidate) {
				return candidate
			}
		}
	}
	return ""
}
