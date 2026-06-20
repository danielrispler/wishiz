package extractors

import (
	"net/url"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// merchantPriceSelectors maps a known merchant to its price selectors, tried in
// order (first non-empty wins). Ported from the retired fastpath merchant
// handlers but DEMOTED to a MEDIUM voter: a merchant selector can only win by
// agreeing with structured data, never auto-complete against it. Name and image
// are deliberately left to the generic structured extractors to avoid fake
// corroboration (the merchant selectors picked the same <h1>/og:image anyway).
var merchantPriceSelectors = map[string][]string{
	"zara.com":           {"span.price__amount"},
	"hm.com":             {`[data-testid="formatted-value"]`, `[data-testid="product-price"]`, ".price-value"},
	"uniqlo.com":         {".price-box"},
	"nike.com":           {`[data-test="product-price"]`},
	"massimodutti.com":   {"span.price__amount", "span.price-amount", ".price-amount"},
	"crzyoga.com":        {`[data-testid="productdescriptionprice-price"]`, `[itemprop="price"]`, ".price"},
	"addictonline.co.il": {`[data-testid="product-price"]`, ".price", ".product-price"},
	"vuoriclothing.com":  {`[data-testid="productdescriptionprice-price"]`, `[data-testid="product-price"]`, ".price"},
	"de-rococo.co.il":    {".price", ".product-price", ".current-price"},
	"factory54.co.il":    {".price > .sale-price", ".sale-price"},
	"aloyoga.com":        {".Price", `[class*="Price"]`},
	"lululemon.com":      {`[class*="price_price__"]`},
}

// Merchant emits a single MEDIUM price candidate from the merchant-specific
// selector for the page's host, when the host is a known merchant.
func Merchant(document *goquery.Document, base *url.URL) []Candidate {
	if base == nil {
		return nil
	}
	selectors := merchantSelectorsFor(base.Hostname())
	if selectors == nil {
		return nil
	}

	for _, selector := range selectors {
		raw := textOf(document, selector)
		if raw == "" {
			continue
		}
		if candidate, ok := newPriceCandidate(SourceMerchant, "", raw); ok {
			return []Candidate{candidate}
		}
	}
	return nil
}

func merchantSelectorsFor(host string) []string {
	normalized := strings.ToLower(host)
	for domain, selectors := range merchantPriceSelectors {
		// Match the exact host or a sub-domain of it, not any substring — a
		// substring match would let fake-nike.com borrow nike.com's selectors.
		if normalized == domain || strings.HasSuffix(normalized, "."+domain) {
			return selectors
		}
	}
	return nil
}
