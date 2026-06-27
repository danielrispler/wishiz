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
	candidates = append(candidates, flightCandidates(reconstructFlightBlob(rawHTML), base, seen)...)

	return candidates
}

// flightMarker introduces each React Server Component "flight" chunk that
// Next.js App Router streams inline as self.__next_f.push([N,"…"]).
const flightMarker = "__next_f.push("

// reconstructFlightBlob walks every __next_f.push([N,"…"]) call in rawHTML and
// concatenates the decoded string argument (parts[1]) of each in document order,
// rebuilding the streamed RSC payload. Unmarshalling parts[1] into a Go string
// does the JS/JSON unescaping for free (\" → ", \\n → newline), so the result is
// the raw flight text. The [0] bootstrap push (a single-element array) is skipped.
// The blob itself is NOT valid JSON — it is line-oriented flight rows — so callers
// scan it for balanced JSON islands rather than unmarshalling it whole.
func reconstructFlightBlob(rawHTML string) string {
	var blob strings.Builder
	rest := rawHTML
	for {
		marker := strings.Index(rest, flightMarker)
		if marker < 0 {
			break
		}
		rest = rest[marker+len(flightMarker):]
		start := strings.IndexByte(rest, '[')
		if start < 0 {
			break
		}
		arg := firstBalancedSpan(rest[start:], '[', ']')
		if arg == "" {
			continue
		}
		rest = rest[start+len(arg):]

		var parts []json.RawMessage
		if err := json.Unmarshal([]byte(arg), &parts); err != nil || len(parts) < 2 {
			continue
		}
		var chunk string
		if err := json.Unmarshal(parts[1], &chunk); err != nil {
			continue
		}
		blob.WriteString(chunk)
	}
	return blob.String()
}

// strongPriceContainers are the GraphQL/commerce wrapper keys whose nested
// {value:{amount,currency}} Money is the genuine selling price. Restricting the
// container-price scan to this allowlist is what keeps decoy amounts (listPrice,
// addOns, shipping) — which live under other keys — from ever voting on price.
var strongPriceContainers = map[string]bool{
	"primaryPrice": true,
	"sellingPrice": true,
	"offers":       true,
}

// flightCandidates scans a reconstructed flight blob for balanced {…} JSON
// islands and folds each through both productShapedCandidates (Part A — any island
// co-locating a name and a flat/one-level price benefits, with zero schema
// knowledge) and the container-keyed Money the generic readers miss (Part B). It
// threads the shared seen map so flight values dedupe against the marker/script
// candidates already emitted.
//
// Part B is frequency-ranked: a single page embeds many products (Wayfair-class
// PDPs carry recommendation carousels, each with its own primaryPrice), so naively
// emitting every allowlisted container price floods consensus with decoys and
// deadlocks it into price_conflict. The MAIN product's amount recurs across the
// flight payload (primaryPrice + sellingPrice + repeated Money nodes) while each
// embedded product's price appears once, so only the most-frequent container
// price(s) are emitted (see dominantFlightPrices).
func flightCandidates(blob string, base *url.URL, seen map[string]struct{}) []Candidate {
	if blob == "" {
		return nil
	}
	var out []Candidate
	moneyFreq := map[string]int{}
	var containerPrices []flightContainerPrice
	rest := blob
	for {
		start := strings.IndexByte(rest, '{')
		if start < 0 {
			break
		}
		island := firstBalancedSpan(rest[start:], '{', '}')
		if island == "" {
			break
		}
		rest = rest[start+len(island):]

		var decoded any
		if err := json.Unmarshal([]byte(island), &decoded); err != nil {
			continue
		}
		for _, node := range flattenJSONMaps(decoded) {
			if amount := stringValue(node["amount"]); amount != "" {
				if code := currencyCodeOf(node); code != "" {
					moneyFreq[amount+"|"+strings.ToUpper(code)]++
				}
			}
			out = append(out, productShapedCandidates(node, base, seen)...)
			containerPrices = append(containerPrices, containerPriceEntries(node)...)
		}
	}
	out = append(out, dominantFlightPrices(containerPrices, moneyFreq, seen)...)
	return out
}

// flightContainerPrice is an allowlisted container price plus its amount|CODE key,
// used to frequency-rank flight prices before emission.
type flightContainerPrice struct {
	candidate Candidate
	amount    string
	code      string
}

// dominantFlightPrices keeps only the container price(s) whose amount recurs most
// across the whole flight payload (moneyFreq), so a page full of recommendation /
// add-on prices can't deadlock price consensus. An exact frequency tie keeps all
// tied candidates — the genuinely-ambiguous case falls back to the displayed-price
// disambiguation in consensus rather than guessing. Emission dedupes via the shared
// seen map, matching the original "price:"+amount+"|"+code key.
func dominantFlightPrices(
	prices []flightContainerPrice, moneyFreq map[string]int, seen map[string]struct{},
) []Candidate {
	maxFreq := 0
	for _, price := range prices {
		if freq := moneyFreq[price.amount+"|"+price.code]; freq > maxFreq {
			maxFreq = freq
		}
	}
	var out []Candidate
	for _, price := range prices {
		if moneyFreq[price.amount+"|"+price.code] != maxFreq {
			continue
		}
		dedupKey := "price:" + price.amount + "|" + price.code
		if _, dup := seen[dedupKey]; dup {
			continue
		}
		seen[dedupKey] = struct{}{}
		out = append(out, price.candidate)
	}
	return out
}

// containerPriceCandidates emits a price candidate for each allowlisted price
// container in node whose nested Money carries BOTH an amount and an explicit
// currency. Disambiguation is by container key — never by first/lowest amount —
// so amounts under non-allowlisted keys are never even scanned. A missing currency
// emits nothing (never assigns a bare $). It votes only on price, never on name.
// (flightCandidates instead frequency-ranks via containerPriceEntries; this remains
// the single-node entry point used directly by unit tests.)
func containerPriceCandidates(node map[string]any, seen map[string]struct{}) []Candidate {
	var out []Candidate
	for _, entry := range containerPriceEntries(node) {
		dedupKey := "price:" + entry.amount + "|" + entry.code
		if _, dup := seen[dedupKey]; dup {
			continue
		}
		seen[dedupKey] = struct{}{}
		out = append(out, entry.candidate)
	}
	return out
}

// containerPriceEntries pulls every allowlisted container price out of a single
// node, keyed by amount|CODE for frequency ranking. No dedup / seen handling — the
// caller decides which to emit.
func containerPriceEntries(node map[string]any) []flightContainerPrice {
	var out []flightContainerPrice
	for key, value := range node {
		if !strongPriceContainers[key] {
			continue
		}
		amount, currency := nestedValueAmount(value)
		if amount == "" || currency == "" {
			continue
		}
		code := strings.ToUpper(currency)
		candidate, ok := newPriceCandidate(SourceJSState, code, joinPrice(code, amount))
		if !ok {
			continue
		}
		out = append(out, flightContainerPrice{candidate: candidate, amount: amount, code: code})
	}
	return out
}

// nestedValueAmount descends a price-container subtree and returns the first
// Money it finds: a map holding BOTH an "amount" and a currency (the GraphQL
// Money.value shape, e.g. primaryPrice.price.value). Requiring amount+currency
// in the SAME map keeps it from latching onto a bare amount and gives the
// container-keyed price its explicit HIGH currency.
func nestedValueAmount(value any) (amount string, currency string) {
	switch typed := value.(type) {
	case map[string]any:
		if amt := stringValue(typed["amount"]); amt != "" {
			if code := currencyCodeOf(typed); code != "" {
				return amt, code
			}
		}
		for _, key := range []string{"value", "price"} {
			if amt, code := nestedValueAmount(typed[key]); amt != "" {
				return amt, code
			}
		}
		for child, nested := range typed {
			if child == "value" || child == "price" {
				continue
			}
			if amt, code := nestedValueAmount(nested); amt != "" {
				return amt, code
			}
		}
	case []any:
		for _, entry := range typed {
			if amt, code := nestedValueAmount(entry); amt != "" {
				return amt, code
			}
		}
	}
	return "", ""
}

// currencyCodeOf reads an ISO-4217 code from a Money/price map, handling both the
// object form (currency:{code:"USD"}) and the flat string forms (currencyCode /
// currency:"USD") — the shapes jsPrice's flat lookup misses.
func currencyCodeOf(node map[string]any) string {
	if nested, ok := node["currency"].(map[string]any); ok {
		if code := stringValue(nested["code"]); code != "" {
			return code
		}
	}
	return firstStringField(node, "currencyCode", "currency", "priceCurrency")
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

// balancedJSONAfter finds marker in s and returns the embedded product object.
// It handles both direct assignment (window.__NUXT__={...}) and the IIFE wrapper
// (window.__NUXT__=(function(){return {...}}())) that frameworks like Nuxt emit:
// for the wrapper the first { after the marker is the function body, so it skips
// to the object after the first top-level `return`. The scan is string-aware, so
// a string literal containing `return {fake}` does not lock onto the fake.
func balancedJSONAfter(s, marker string) string {
	index := strings.Index(s, marker)
	if index < 0 {
		return ""
	}
	rest := strings.TrimLeft(s[index+len(marker):], " \t\r\n=")

	// IIFE wrapper: advance past the function preamble to the returned object.
	if strings.HasPrefix(rest, "(") || strings.HasPrefix(rest, "function") {
		if r := indexAfterReturn(rest); r >= 0 {
			rest = rest[r:]
		}
	}
	return firstBalancedObject(rest)
}

// indexAfterReturn finds the first `return` keyword that is not inside a string
// literal and returns the index of the `{` that follows it, or -1.
func indexAfterReturn(s string) int {
	inString := false
	escaped := false
	for i := 0; i < len(s); i++ {
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
		if c == '"' {
			inString = true
			continue
		}
		if c == 'r' && isReturnKeywordAt(s, i) {
			if brace := strings.IndexByte(s[i:], '{'); brace >= 0 {
				return i + brace
			}
			return -1
		}
	}
	return -1
}

// isReturnKeywordAt reports whether s has the whole word "return" at index i.
func isReturnKeywordAt(s string, i int) bool {
	const kw = "return"
	if i+len(kw) > len(s) || s[i:i+len(kw)] != kw {
		return false
	}
	if i > 0 && isWordByte(s[i-1]) {
		return false
	}
	if j := i + len(kw); j < len(s) && isWordByte(s[j]) {
		return false
	}
	return true
}

func isWordByte(b byte) bool {
	return b == '_' ||
		(b >= '0' && b <= '9') ||
		(b >= 'a' && b <= 'z') ||
		(b >= 'A' && b <= 'Z')
}

// firstBalancedObject returns the first balanced {...} object in s, counting
// braces only outside of string literals.
func firstBalancedObject(s string) string {
	return firstBalancedSpan(s, '{', '}')
}

// firstBalancedSpan returns the first balanced open…close span in s, counting
// delimiters only outside of string literals (so a brace/bracket inside a quoted
// value never miscounts). Used for {…} JSON objects and the bracket-heavy
// [N,"…"] argument of __next_f.push.
func firstBalancedSpan(s string, open, closeByte byte) string {
	start := strings.IndexByte(s, open)
	if start < 0 {
		return ""
	}

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
		case open:
			depth++
		case closeByte:
			depth--
			if depth == 0 {
				return s[start : i+1]
			}
		}
	}
	return ""
}
