package extractors

import (
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

var whitespacePattern = regexp.MustCompile(`\s+`)

func normalizeText(value string) string {
	return whitespacePattern.ReplaceAllString(strings.TrimSpace(value), " ")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if normalized := normalizeText(value); normalized != "" {
			return normalized
		}
	}
	return ""
}

func textOf(document *goquery.Document, selector string) string {
	return normalizeText(document.Find(selector).First().Text())
}

func metaContent(document *goquery.Document, key string, attr ...string) string {
	attributeName := "property"
	if len(attr) > 0 && attr[0] != "" {
		attributeName = attr[0]
	}
	content, _ := document.Find(`meta[` + attributeName + `="` + key + `"]`).First().Attr("content")
	return normalizeText(content)
}

// firstSource returns the first usable source URL from the given attributes of
// the matched elements, skipping obvious logo/icon/placeholder assets.
func firstSource(document *goquery.Document, selector string, attributes ...string) string {
	var resolved string
	document.Find(selector).EachWithBreak(func(_ int, selection *goquery.Selection) bool {
		for _, attribute := range attributes {
			value, ok := selection.Attr(attribute)
			if !ok {
				continue
			}
			candidate := parseSourceValue(value)
			if candidate == "" || looksLikeNonProductImage(candidate) {
				continue
			}
			resolved = candidate
			return false
		}
		return true
	})
	return resolved
}

func looksLikeNonProductImage(candidate string) bool {
	return IsNonProductImageURL(candidate)
}

// nonProductImageMarkers are filename tokens that mark a non-product asset.
var nonProductImageMarkers = map[string]bool{
	"logo":        true,
	"icon":        true,
	"sprite":      true,
	"placeholder": true,
	"favicon":     true,
}

// genericImageBasenames are whole-filename generic store/share/placeholder assets
// (e.g. a Shopify theme's default `social-image.jpg`). Unlike the single-token
// markers above these are multi-token names, so they are matched as an ANCHORED
// filename prefix (start of the filename, followed by end / `.` / `-` / `_`) to
// catch size suffixes like `social-image_1024x.jpg` while never rejecting a real
// product whose name merely contains the substring (e.g. `dog-image.jpg`,
// `casino-image.jpg`).
var genericImageBasenames = []string{
	"social-image", "social_image",
	"no-image", "noimage",
	"default-product", "default-image",
	"share-image", "og-image",
}

// IsNonProductImageURL reports whether rawURL looks like a logo/icon/sprite/
// placeholder/favicon asset rather than a product image. It inspects the LAST
// path segment (the filename) split on separator characters and matches whole
// tokens, so a marker that appears only as a substring of the host or a
// non-marker filename — silicon-power.com, logitech.com, products/silicon-case.jpg
// — is not rejected. Single source of truth shared by the image extractor and
// the application-layer ValidateImageURL.
func IsNonProductImageURL(rawURL string) bool {
	trimmed := strings.TrimSpace(rawURL)
	if trimmed == "" {
		return false
	}

	path := trimmed
	if parsed, err := url.Parse(trimmed); err == nil && parsed.Path != "" {
		path = parsed.Path
	}
	if strings.Contains(strings.ToLower(path), "/favicon") {
		return true
	}

	segment := path
	if i := strings.LastIndexByte(segment, '/'); i >= 0 {
		segment = segment[i+1:]
	}
	lowerSegment := strings.ToLower(segment)
	for _, token := range strings.FieldsFunc(lowerSegment, func(r rune) bool {
		return r == '-' || r == '_' || r == '.'
	}) {
		if nonProductImageMarkers[token] {
			return true
		}
	}
	for _, name := range genericImageBasenames {
		if lowerSegment == name ||
			strings.HasPrefix(lowerSegment, name+".") ||
			strings.HasPrefix(lowerSegment, name+"-") ||
			strings.HasPrefix(lowerSegment, name+"_") {
			return true
		}
	}
	return false
}

// parseSourceValue pulls the first URL out of a src/srcset attribute value.
func parseSourceValue(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	if strings.Contains(trimmed, ",") {
		firstCandidate := strings.TrimSpace(strings.Split(trimmed, ",")[0])
		if firstField := strings.Fields(firstCandidate); len(firstField) > 0 {
			return firstField[0]
		}
	}
	if fields := strings.Fields(trimmed); len(fields) > 0 {
		return fields[0]
	}
	return trimmed
}

// resolveURL resolves candidate against base, returning an absolute URL.
func resolveURL(base *url.URL, candidate string) string {
	if candidate == "" {
		return ""
	}
	parsed, err := url.Parse(candidate)
	if err != nil {
		return candidate
	}
	if base == nil {
		return parsed.String()
	}
	return base.ResolveReference(parsed).String()
}

// flattenJSONMaps walks any decoded JSON value and returns every map node it
// contains, depth-first, so JSON-LD @graph / nested offers are all visited.
func flattenJSONMaps(value any) []map[string]any {
	switch typed := value.(type) {
	case map[string]any:
		result := make([]map[string]any, 0, len(typed)+1)
		result = append(result, typed)
		for _, nested := range typed {
			result = append(result, flattenJSONMaps(nested)...)
		}
		return result
	case []any:
		var result []map[string]any
		for _, nested := range typed {
			result = append(result, flattenJSONMaps(nested)...)
		}
		return result
	default:
		return nil
	}
}

func isProductNode(node map[string]any) bool {
	switch typed := node["@type"].(type) {
	case string:
		return strings.EqualFold(typed, "Product")
	case []any:
		for _, entry := range typed {
			if text, ok := entry.(string); ok && strings.EqualFold(text, "Product") {
				return true
			}
		}
	}
	return false
}

func stringValue(value any) string {
	switch v := value.(type) {
	case string:
		return normalizeText(v)
	case float64:
		return normalizeText(strconv.FormatFloat(v, 'f', -1, 64))
	case int:
		return normalizeText(strconv.Itoa(v))
	case int64:
		return normalizeText(strconv.FormatInt(v, 10))
	default:
		return ""
	}
}

func readImage(value any) string {
	switch typed := value.(type) {
	case string:
		return normalizeText(typed)
	case []any:
		for _, entry := range typed {
			if image := readImage(entry); image != "" {
				return image
			}
		}
	case map[string]any:
		return firstNonEmpty(stringValue(typed["url"]), stringValue(typed["@id"]))
	}
	return ""
}

// looksLikeNonPrimaryPrice flags price contexts that usually carry a secondary
// amount (comparison, installment, shipping) so the consensus engine can
// down-weight them.
func looksLikeNonPrimaryPrice(context string) bool {
	normalized := strings.ToLower(context)
	for _, marker := range []string{
		"compare", "was ", "list price", "save ", "installment",
		"finance", "shipping", "per month", "monthly",
	} {
		if strings.Contains(normalized, marker) {
			return true
		}
	}
	return false
}
