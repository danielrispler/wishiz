package extractors

import (
	"encoding/json"
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// JSONLD extracts name/image/price candidates from schema.org Product JSON-LD.
// It is the most authoritative structured source: walks @graph, @type arrays,
// nested offers and AggregateOffer.
func JSONLD(document *goquery.Document, base *url.URL) []Candidate {
	var products []map[string]any
	document.Find(`script[type="application/ld+json"]`).Each(func(_ int, selection *goquery.Selection) {
		payload := strings.TrimSpace(selection.Text())
		if payload == "" {
			return
		}
		var decoded any
		if err := json.Unmarshal([]byte(payload), &decoded); err != nil {
			return
		}
		for _, node := range flattenJSONMaps(decoded) {
			if isProductNode(node) {
				products = append(products, node)
			}
		}
	})

	// Emit candidates from a SINGLE primary product. A page often carries several
	// Product nodes (related/recommended carousels), each with its own offer; if
	// every one voted, two authoritative-but-different prices would manufacture a
	// false conflict and force needs_review.
	primary := primaryProductNode(products, base)
	if primary == nil {
		return nil
	}

	var candidates []Candidate
	if name := stringValue(primary["name"]); name != "" {
		candidates = append(candidates, Candidate{
			Field: FieldName, Value: name, Source: SourceJSONLD, Raw: name,
		})
	}
	if image := readImage(primary["image"]); image != "" {
		candidates = append(candidates, Candidate{
			Field: FieldImage, Value: resolveURL(base, image), Source: SourceJSONLD, Raw: image,
		})
	}
	candidates = append(candidates, jsonldOfferPrices(primary["offers"])...)
	return candidates
}

// primaryProductNode picks the focus product from all Product JSON-LD nodes on a
// page: first the one whose url/@id matches the canonical page URL, then the
// first one carrying an offer (the focus product usually does), then the first
// product node at all (so name/image still surface even without an offer).
func primaryProductNode(products []map[string]any, base *url.URL) map[string]any {
	if len(products) == 0 {
		return nil
	}
	if base != nil {
		for _, product := range products {
			if productMatchesURL(product, base) {
				return product
			}
		}
	}
	for _, product := range products {
		if _, ok := product["offers"]; ok {
			return product
		}
	}
	return products[0]
}

// productMatchesURL reports whether a product node's url/@id/mainEntityOfPage
// points at the same page path as base.
func productMatchesURL(node map[string]any, base *url.URL) bool {
	for _, key := range []string{"url", "@id", "mainEntityOfPage"} {
		raw := stringValue(node[key])
		if raw == "" {
			continue
		}
		parsed, err := url.Parse(raw)
		if err != nil {
			continue
		}
		if parsed.Host != "" && !strings.EqualFold(parsed.Host, base.Host) {
			continue
		}
		if strings.EqualFold(strings.TrimRight(parsed.Path, "/"), strings.TrimRight(base.Path, "/")) {
			return true
		}
	}
	return false
}

func jsonldOfferPrices(value any) []Candidate {
	switch typed := value.(type) {
	case map[string]any:
		var out []Candidate
		currency := stringValue(typed["priceCurrency"])
		amount := stringValue(typed["price"])
		if amount == "" {
			amount = stringValue(typed["lowPrice"]) // AggregateOffer
		}
		if amount != "" {
			if candidate, ok := newPriceCandidate(SourceJSONLD, currency, joinPrice(currency, amount)); ok {
				out = append(out, candidate)
			}
		}
		if currency != "" {
			out = append(out, Candidate{
				Field: FieldCurrency, Value: strings.ToUpper(currency), Source: SourceJSONLD, Raw: currency,
			})
		}
		if nested, ok := typed["offers"]; ok {
			out = append(out, jsonldOfferPrices(nested)...)
		}
		return out
	case []any:
		var out []Candidate
		for _, entry := range typed {
			out = append(out, jsonldOfferPrices(entry)...)
		}
		return out
	}
	return nil
}
