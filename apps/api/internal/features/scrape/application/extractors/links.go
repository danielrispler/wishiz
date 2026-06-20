package extractors

import (
	"net/url"

	"github.com/PuerkitoBio/goquery"
)

// Links emits link candidates: <link rel=canonical>, og:url, and the final
// fetched URL as a guaranteed fallback. Cleaning (tracking-param strip) happens
// in the validation gate, not here.
func Links(document *goquery.Document, base *url.URL, finalURL string) []Candidate {
	var candidates []Candidate

	if canonical, ok := document.Find(`link[rel="canonical"]`).First().Attr("href"); ok {
		if resolved := resolveURL(base, normalizeText(canonical)); resolved != "" {
			candidates = append(candidates, Candidate{
				Field: FieldLink, Value: resolved, Source: SourceCanonical, Raw: canonical,
			})
		}
	}

	if ogURL := metaContent(document, "og:url", "property"); ogURL != "" {
		if resolved := resolveURL(base, ogURL); resolved != "" {
			candidates = append(candidates, Candidate{
				Field: FieldLink, Value: resolved, Source: SourceOpenGraph, Raw: ogURL,
			})
		}
	}

	if finalURL != "" {
		candidates = append(candidates, Candidate{
			Field: FieldLink, Value: finalURL, Source: SourceFinalURL, Raw: finalURL,
		})
	}

	return candidates
}
