package extractors

import (
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// OpenGraph extracts candidates from OpenGraph / Twitter / standard meta tags
// and the <title>/<h1> elements. og:title/og:image are decent (corroborating)
// sources; og:price / product:price meta are authoritative for price.
func OpenGraph(document *goquery.Document, base *url.URL) []Candidate {
	var candidates []Candidate

	add := func(field Field, source SourceName, value string) {
		if value != "" {
			candidates = append(candidates, Candidate{Field: field, Value: value, Source: source, Raw: value})
		}
	}

	// Name: og:title / twitter:title from meta, plus <h1> and <title> as
	// independent corroborating voters.
	add(FieldName, SourceOpenGraph, firstNonEmpty(
		metaContent(document, "og:title", "property"),
		metaContent(document, "twitter:title", "name"),
	))
	add(FieldName, SourceH1, textOf(document, "h1"))
	add(FieldName, SourceTitle, normalizeText(document.Find("title").First().Text()))

	// Image: og:image / twitter:image.
	image := firstNonEmpty(
		metaContent(document, "og:image", "property"),
		metaContent(document, "twitter:image", "name"),
		metaContent(document, "image", "name"),
	)
	if image != "" {
		candidates = append(candidates, Candidate{
			Field: FieldImage, Value: resolveURL(base, image), Source: SourceOpenGraph, Raw: image,
		})
	}

	// Price: product:price:* / og:price:* meta.
	priceText := firstNonEmpty(
		metaContent(document, "product:price:amount", "property"),
		metaContent(document, "og:price:amount", "property"),
		metaContent(document, "price", "name"),
	)
	priceCurrency := firstNonEmpty(
		metaContent(document, "product:price:currency", "property"),
		metaContent(document, "og:price:currency", "property"),
	)
	if priceText != "" {
		if candidate, ok := newPriceCandidate(SourceOpenGraph, priceCurrency, joinPrice(priceCurrency, priceText)); ok {
			candidates = append(candidates, candidate)
		}
	}
	if priceCurrency != "" {
		candidates = append(candidates, Candidate{
			Field: FieldCurrency, Value: strings.ToUpper(priceCurrency), Source: SourceOpenGraph, Raw: priceCurrency,
		})
	}

	return candidates
}
