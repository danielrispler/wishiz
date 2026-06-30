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
			candidates = append(candidates, aggregatePriceRange(node, seen)...)
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
// Part B is decoy-filtered: a single page embeds many products (Wayfair-class PDPs
// carry recommendation carousels, each with its own primaryPrice), so naively
// emitting every allowlisted container price floods consensus with decoys and
// deadlocks it into price_conflict. dominantFlightPrices keeps only the price that
// recurs across DISTINCT container keys of the same product (the main-product
// signal), or emits all and lets consensus flag/disambiguate when that signal is
// absent.
func flightCandidates(blob string, base *url.URL, seen map[string]struct{}) []Candidate {
	if blob == "" {
		return nil
	}
	var out []Candidate
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
			out = append(out, productShapedCandidates(node, base, seen)...)
			containerPrices = append(containerPrices, containerPriceEntries(node)...)
		}
	}
	out = append(out, dominantFlightPrices(containerPrices, seen)...)
	return out
}

// flightContainerPrice is an allowlisted container price plus its amount|CODE key
// and the container key it came from, used to decoy-filter flight prices by
// distinct-container-key recurrence before emission.
type flightContainerPrice struct {
	candidate Candidate
	amount    string
	code      string
	container string
}

// dominantFlightPrices decides which allowlisted flight container prices to emit.
// A page embeds many products (recommendation carousels, add-ons), each with its
// own primaryPrice, so naively emitting all floods consensus into price_conflict.
//
// The signal that an amount is the MAIN product's price (not a decoy) is that it
// recurs across DISTINCT container KEYS of the same product — primaryPrice AND
// sellingPrice (and/or offers) all carry it. A decoy amount, even when several
// sibling products happen to share it, recurs only under the SAME key
// (primaryPrice), so raw Money-node frequency cannot tell the two apart — counting
// DISTINCT container keys per amount can.
//
// Emit a single price only when one amount is the UNIQUE maximum by distinct-key
// count AND that count is ≥2 (genuine cross-key repetition), or when there is only
// one distinct amount at all (no ambiguity). Otherwise emit every distinct amount,
// leaving consensus to flag price_conflict (→ needs_review) or, when a visible price
// exists, disambiguate by it. Emission dedupes via the shared seen map.
func dominantFlightPrices(prices []flightContainerPrice, seen map[string]struct{}) []Candidate {
	keysByAmount := map[string]map[string]struct{}{}
	for _, price := range prices {
		amountKey := price.amount + "|" + price.code
		set := keysByAmount[amountKey]
		if set == nil {
			set = map[string]struct{}{}
			keysByAmount[amountKey] = set
		}
		set[price.container] = struct{}{}
	}

	emitAll, winner := true, ""
	if len(keysByAmount) > 1 {
		maxKeys, unique := 0, false
		for amountKey, set := range keysByAmount {
			switch {
			case len(set) > maxKeys:
				maxKeys, unique, winner = len(set), true, amountKey
			case len(set) == maxKeys:
				unique = false
			}
		}
		// Trust a single amount only when it recurs across ≥2 distinct container
		// keys and is the sole amount that does so; otherwise stay ambiguous.
		emitAll = !unique || maxKeys < 2
	}

	var out []Candidate
	for _, price := range prices {
		amountKey := price.amount + "|" + price.code
		if !emitAll && amountKey != winner {
			continue
		}
		dedupKey := "price:" + amountKey
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
		out = append(out, flightContainerPrice{candidate: candidate, amount: amount, code: code, container: key})
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

// rangePriceTiers names the price-range key stems in preference order: the
// shopper-facing selling/sale price wins over list/regular/retail (so a discounted
// range reports the sale floor, not the struck-through MSRP). Each stem T matches
// the paired keys low<T>price / high<T>price.
//
// The BARE stem ("" → lowPrice/highPrice) is deliberately EXCLUDED: that schema.org
// AggregateOffer shape is unscoped in a generic state blob — it is just as often a
// category aggregate or a facet/price-filter slider as the product's price. Genuine
// AggregateOffer is recovered by the JSON-LD extractor (gated on @type Product); the
// generic reader only trusts explicit commerce tiers, which are product-specific.
var rangePriceTiers = []string{"selling", "sale", "current", "regular", "list", "retail", "msrp"}

// aggregatePriceRange emits a single "starting at" price candidate from a price
// RANGE map: a node carrying paired low<tier>price + high<tier>price keys. This
// is the schema.org AggregateOffer shape (lowPrice/highPrice) and the bespoke
// commerce-state shape alike — Williams-Sonoma brands (West Elm, Pottery Barn, …)
// embed the price ONLY as __INITIAL_STATE__.aggregatePrice.{low,high}SellingPrice,
// with no Product JSON-LD / og:price for the generic readers to find.
//
// Only the LOW bound is emitted, as ONE candidate — mirroring the JSON-LD
// extractor, which already treats AggregateOffer.lowPrice as the starting price.
// Emitting both bounds would feed consensus two trusted-tier amounts that disagree
// and deadlock price into price_conflict → needs_review (the very failure this
// fixes). The pairing requirement (a lone low<tier>price never qualifies) keeps it
// from latching onto facet/filter sliders, and currency is left empty for the
// locale/TLD inference step — these state blobs rarely carry an explicit code.
func aggregatePriceRange(node map[string]any, seen map[string]struct{}) []Candidate {
	// Probe for low<tier>price / high<tier>price keys directly, allocating the small
	// tier maps only once an actual range key is seen. Most nodes carry none, so the
	// common path is a single ToLower + prefix/suffix check per key and no alloc.
	var lows, highs map[string]string
	for key, value := range node {
		lower := strings.ToLower(key)
		if !strings.HasSuffix(lower, "price") {
			continue
		}
		var bucket *map[string]string
		var tier string
		switch {
		case strings.HasPrefix(lower, "low"):
			tier, bucket = lower[len("low"):len(lower)-len("price")], &lows
		case strings.HasPrefix(lower, "high"):
			tier, bucket = lower[len("high"):len(lower)-len("price")], &highs
		default:
			continue
		}
		amount := stringValue(value)
		if amount == "" {
			continue
		}
		if *bucket == nil {
			*bucket = map[string]string{}
		}
		(*bucket)[tier] = amount
	}
	if lows == nil || highs == nil {
		return nil
	}
	for _, tier := range rangePriceTiers {
		low := lows[tier]
		high := highs[tier]
		if low == "" || high == "" {
			continue
		}
		candidate, ok := newPriceCandidate(SourceJSState, "", low)
		if !ok {
			return nil
		}
		dedupKey := "price:" + candidate.Value + "|" + candidate.Currency
		if _, dup := seen[dedupKey]; dup {
			return nil
		}
		seen[dedupKey] = struct{}{}
		return []Candidate{candidate}
	}
	return nil
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
