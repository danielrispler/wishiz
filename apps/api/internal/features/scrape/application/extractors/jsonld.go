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
	var candidates []Candidate

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
			if !isProductNode(node) {
				continue
			}
			if name := stringValue(node["name"]); name != "" {
				candidates = append(candidates, Candidate{
					Field: FieldName, Value: name, Source: SourceJSONLD, Raw: name,
				})
			}
			if image := readImage(node["image"]); image != "" {
				candidates = append(candidates, Candidate{
					Field: FieldImage, Value: resolveURL(base, image), Source: SourceJSONLD, Raw: image,
				})
			}
			candidates = append(candidates, jsonldOfferPrices(node["offers"])...)
		}
	})

	return candidates
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
