package extractors

import (
	"encoding/json"
	"net/url"
	"strconv"
	"strings"
)

// autoparsePayload is the slice of the ZenRows autoparse product document we map.
// ZenRows owns the parsing; we read only the fields we trust (and price_without_
// discount, used solely by the sanity guard — never emitted as a price).
type autoparsePayload struct {
	Title                string   `json:"title"`
	Price                string   `json:"price"`
	PriceWithoutDiscount string   `json:"price_without_discount"`
	Images               []string `json:"images"`
}

// amazonShorteners are Amazon's link-shortener hosts. They 30x-redirect to a real
// marketplace product page; the app share sheet emits a.co links. They gate the
// autoparse rescue but carry no currency (the resolved final-URL host does).
var amazonShorteners = map[string]bool{
	"a.co":      true,
	"amzn.to":   true,
	"amzn.eu":   true,
	"amzn.asia": true,
	"amzn.com":  true,
}

// amazonMarketplaceCurrency maps an Amazon marketplace registrable domain to its
// listing currency. Used to assign an EXPLICIT currency to the autoparse price
// (which arrives as a bare "$179.00"-style string) from the ZenRows final-URL
// host. A host absent here yields no currency → the import falls to needs_review
// rather than guessing.
var amazonMarketplaceCurrency = map[string]string{
	"amazon.com":    codeUSD,
	"amazon.co.uk":  codeGBP,
	"amazon.de":     codeEUR,
	"amazon.fr":     codeEUR,
	"amazon.es":     codeEUR,
	"amazon.it":     codeEUR,
	"amazon.nl":     codeEUR,
	"amazon.com.be": codeEUR,
	"amazon.ie":     codeEUR,
	"amazon.ca":     "CAD",
	"amazon.com.au": "AUD",
	"amazon.co.jp":  "JPY",
	"amazon.in":     "INR",
	"amazon.com.mx": "MXN",
	"amazon.com.br": "BRL",
	"amazon.se":     "SEK",
	"amazon.pl":     "PLN",
	"amazon.com.tr": "TRY",
	"amazon.sg":     "SGD",
	"amazon.ae":     "AED",
	"amazon.sa":     "SAR",
	"amazon.eg":     "EGP",
}

// normalizeHost lowercases a host and trims a trailing dot so suffix matching is
// stable.
func normalizeHost(host string) string {
	return strings.ToLower(strings.TrimSuffix(strings.TrimSpace(host), "."))
}

// IsAmazonHost reports whether host is an Amazon marketplace domain (amazon.<tld>,
// possibly with a www./smile. subdomain) or an Amazon shortener (a.co, amzn.*).
// It gates the autoparse rescue: the shortener arm matters because a.co hides the
// real marketplace until the fetch resolves it.
func IsAmazonHost(host string) bool {
	host = normalizeHost(host)
	if host == "" {
		return false
	}
	if amazonShorteners[host] {
		return true
	}
	labels := strings.Split(host, ".")
	for i, label := range labels {
		if label == "amazon" && i < len(labels)-1 {
			return true
		}
	}
	return false
}

// AmazonMarketplaceCurrency returns the listing currency for an Amazon
// marketplace host, matching the longest registrable suffix (so www./smile.
// subdomains resolve). ok is false for an unknown/non-marketplace host, in which
// case the caller must NOT assign a currency.
func AmazonMarketplaceCurrency(host string) (string, bool) {
	host = normalizeHost(host)
	for host != "" {
		if code, ok := amazonMarketplaceCurrency[host]; ok {
			return code, true
		}
		i := strings.IndexByte(host, '.')
		if i < 0 {
			break
		}
		host = host[i+1:]
	}
	return "", false
}

// MapAutoparseProduct converts a ZenRows autoparse JSON document into field
// candidates. resolvedHost is the host of the ZenRows final URL (Zr-Final-Url),
// used to assign the marketplace currency; a guessed currency is never emitted
// for an unknown host. base resolves a relative image URL.
//
// Price-sanity guard: autoparse's `price` is observed to sometimes report a
// bundled/accessory price rather than the buy-box price (ADR-0006). When it has
// no parseable amount, or is below half of price_without_discount (a >50% cut —
// too deep to trust against the messy discount string), the price candidate is
// dropped so the import falls to needs_review instead of auto-completing a wrong
// price. Name and image are still emitted.
func MapAutoparseProduct(raw []byte, resolvedHost string, base *url.URL) []Candidate {
	var payload autoparsePayload
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil
	}

	var candidates []Candidate
	if name := normalizeText(payload.Title); name != "" {
		candidates = append(candidates, Candidate{
			Field: FieldName, Value: name, Source: SourceZenRowsAutoparse, Raw: name,
		})
	}
	if image := firstAutoparseImage(payload.Images, base); image != "" {
		candidates = append(candidates, Candidate{
			Field: FieldImage, Value: image, Source: SourceZenRowsAutoparse, Raw: image,
		})
	}
	if price, ok := autoparsePriceCandidate(payload, resolvedHost); ok {
		candidates = append(candidates, price)
	}
	return candidates
}

// autoparsePriceCandidate applies the price-sanity guard then builds a FieldPrice
// candidate with the marketplace currency resolved from the final-URL host.
func autoparsePriceCandidate(payload autoparsePayload, resolvedHost string) (Candidate, bool) {
	amount, _, hasAmount, _ := normalizePriceParts(payload.Price)
	if !hasAmount {
		return Candidate{}, false
	}
	if suspiciousDiscount(amount, payload.PriceWithoutDiscount) {
		return Candidate{}, false
	}
	currency, _ := AmazonMarketplaceCurrency(resolvedHost)
	return newPriceCandidate(SourceZenRowsAutoparse, currency, payload.Price)
}

// suspiciousDiscount reports whether the autoparse price is implausibly far below
// its own price_without_discount (more than 50% off), which signals the price
// field captured a bundled/accessory price rather than the buy-box price.
func suspiciousDiscount(amount, priceWithoutDiscount string) bool {
	pwdAmount, _, hasPWD, _ := normalizePriceParts(priceWithoutDiscount)
	if !hasPWD {
		return false
	}
	price, err1 := strconv.ParseFloat(amount, 64)
	full, err2 := strconv.ParseFloat(pwdAmount, 64)
	if err1 != nil || err2 != nil || full <= 0 {
		return false
	}
	return price < 0.5*full
}

func firstAutoparseImage(images []string, base *url.URL) string {
	for _, image := range images {
		if image = strings.TrimSpace(image); image != "" {
			return resolveURL(base, image)
		}
	}
	return ""
}
