package extractors

import (
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// brandImageSelectors are site-level brand assets, in display-quality order: a
// clean square brand mark renders best in a product card, so the touch icon
// leads, then the favicon, and og:image is consulted last (in BrandImage) since
// an og:image rejected as a product image is usually a wide logo/banner.
var brandImageSelectors = []string{
	`link[rel="apple-touch-icon"]`,
	`link[rel="apple-touch-icon-precomposed"]`,
	`link[rel="icon"]`,
	`link[rel="shortcut icon"]`,
}

// BrandImage returns the best site brand asset to use as a display fallback when
// no product image survives consensus. It is deliberately NOT a Candidate /
// consensus voter and adds no SourceName, so it never touches AllSourceNames()
// or the price_source CHECK — it is a direct display fallback, not a vote.
//
// Order is display-quality, not resolution: apple-touch-icon (square brand mark)
// → icon/favicon → og:image (last; a rejected-as-product og:image is typically a
// logo/banner). The returned URL is absolute http(s); ok is false when nothing
// usable is found.
func BrandImage(document *goquery.Document, base *url.URL) (string, bool) {
	for _, selector := range brandImageSelectors {
		if href, ok := document.Find(selector).First().Attr("href"); ok {
			if resolved, ok := usableBrandURL(base, href); ok {
				return resolved, true
			}
		}
	}
	if og := metaContent(document, "og:image", "property"); og != "" {
		if resolved, ok := usableBrandURL(base, og); ok {
			return resolved, true
		}
	}
	return "", false
}

// usableBrandURL resolves raw against base and keeps it only if it is an
// absolute http(s) URL (no data: URIs). Unlike product images, brand assets are
// NOT run through IsNonProductImageURL — a logo/favicon is exactly what we want.
func usableBrandURL(base *url.URL, raw string) (string, bool) {
	resolved := resolveURL(base, normalizeText(raw))
	if resolved == "" {
		return "", false
	}
	parsed, err := url.Parse(resolved)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return "", false
	}
	if strings.HasPrefix(strings.ToLower(resolved), "data:") {
		return "", false
	}
	return resolved, true
}
