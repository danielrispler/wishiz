package extractors

import (
	"encoding/json"
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// jsStateMarkers are common client-side state globals that embed product data.
var jsStateMarkers = []string{
	"__NEXT_DATA__",
	"__NUXT__",
	"__INITIAL_STATE__",
	"__APOLLO_STATE__",
	"__PRELOADED_STATE__",
}

// JSState extracts candidates from embedded JS/JSON application state
// (__NEXT_DATA__, window.__NUXT__, <script type="application/json">, …). It is
// a decent (MEDIUM) source: it deep-scans for product-shaped maps rather than
// relying on schema.org typing, so it is heuristic and never authoritative.
func JSState(document *goquery.Document, rawHTML string, base *url.URL) []Candidate {
	var candidates []Candidate
	seen := map[string]struct{}{}

	emit := func(payload string) {
		payload = strings.TrimSpace(payload)
		if payload == "" || payload[0] != '{' && payload[0] != '[' {
			return
		}
		var decoded any
		if err := json.Unmarshal([]byte(payload), &decoded); err != nil {
			return
		}
		for _, node := range flattenJSONMaps(decoded) {
			candidates = append(candidates, productShapedCandidates(node, base, seen)...)
		}
	}

	document.Find(`script[type="application/json"]`).Each(func(_ int, selection *goquery.Selection) {
		emit(selection.Text())
	})
	for _, marker := range jsStateMarkers {
		emit(balancedJSONAfter(rawHTML, marker))
	}

	return candidates
}

// productShapedCandidates emits candidates from a single JSON map only when it
// looks like a product: a name-ish field plus a price-ish signal in the SAME
// map (keeps precision high — a wrong price is worse than a missing one).
func productShapedCandidates(node map[string]any, base *url.URL, seen map[string]struct{}) []Candidate {
	name := firstStringField(node, "name", "title", "productName", "displayName")
	amount, currency := jsPrice(node)
	if name == "" || amount == "" {
		return nil
	}

	var out []Candidate
	if _, ok := seen["name:"+name]; !ok {
		seen["name:"+name] = struct{}{}
		out = append(out, Candidate{Field: FieldName, Value: name, Source: SourceJSState, Raw: name})
	}
	if candidate, ok := newPriceCandidate(SourceJSState, currency, joinPrice(currency, amount)); ok {
		key := "price:" + amount + "|" + currency
		if _, dup := seen[key]; !dup {
			seen[key] = struct{}{}
			out = append(out, candidate)
		}
	}
	if image := firstStringField(node, "image", "imageUrl", "img", "featuredImage"); image != "" {
		if _, ok := seen["image:"+image]; !ok {
			seen["image:"+image] = struct{}{}
			out = append(out, Candidate{Field: FieldImage, Value: resolveURL(base, image), Source: SourceJSState, Raw: image})
		}
	}
	return out
}

// jsPrice pulls an amount+currency pair from a JS state map, handling both flat
// keys and nested {amount, currencyCode} shapes.
func jsPrice(node map[string]any) (amount string, currency string) {
	currency = firstStringField(node, "currency", "currencyCode", "priceCurrency")
	for _, key := range []string{"price", "amount", "currentPrice", "salePrice", "listPrice"} {
		switch value := node[key].(type) {
		case string, float64, int, int64:
			if amount = stringValue(value); amount != "" {
				return amount, currency
			}
		case map[string]any:
			if nested := stringValue(value["amount"]); nested != "" {
				if currency == "" {
					currency = firstStringField(value, "currencyCode", "currency", "priceCurrency")
				}
				return nested, currency
			}
		}
	}
	return "", currency
}

func firstStringField(node map[string]any, keys ...string) string {
	for _, key := range keys {
		if value := stringValue(node[key]); value != "" {
			return value
		}
		if nested, ok := node[key].(map[string]any); ok {
			if value := firstNonEmpty(stringValue(nested["url"]), stringValue(nested["src"]), stringValue(nested["value"])); value != "" {
				return value
			}
		}
	}
	return ""
}

// balancedJSONAfter finds marker in s, then returns the first balanced {...}
// object that follows it (string-aware so braces inside strings don't count).
func balancedJSONAfter(s, marker string) string {
	index := strings.Index(s, marker)
	if index < 0 {
		return ""
	}
	start := strings.IndexByte(s[index:], '{')
	if start < 0 {
		return ""
	}
	start += index

	depth := 0
	inString := false
	escaped := false
	for i := start; i < len(s); i++ {
		c := s[i]
		if inString {
			switch {
			case escaped:
				escaped = false
			case c == '\\':
				escaped = true
			case c == '"':
				inString = false
			}
			continue
		}
		switch c {
		case '"':
			inString = true
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return s[start : i+1]
			}
		}
	}
	return ""
}
