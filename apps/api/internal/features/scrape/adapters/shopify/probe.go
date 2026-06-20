// Package shopify probes Shopify storefronts for authoritative product data via
// the public /products/<handle>.json endpoint. It is the biggest lever for the
// long tail of Shopify stores: ~100% accurate when applicable, and even catches
// stores that omit the usual Shopify detection markers (the handle is in the URL).
package shopify

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/adapters/httpfetch"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

const probeTimeout = 6 * time.Second

// Probe fetches Shopify product JSON. The HTTP client re-validates every
// redirect hop through the SSRF guard, exactly like the other fetch paths.
type Probe struct {
	client   *http.Client
	resolver scrapeapp.HostResolver
}

func NewProbe(resolver scrapeapp.HostResolver) *Probe {
	return &Probe{
		client: &http.Client{
			Timeout: probeTimeout,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if err := scrapeapp.IsRedirectAllowed(req.Context(), resolver, req.URL.String()); err != nil {
					return err
				}
				if len(via) >= 5 {
					return fmt.Errorf("too many redirects")
				}
				return nil
			},
		},
		resolver: resolver,
	}
}

// Candidates probes the product JSON for pageURL and returns Shopify-sourced
// candidates. It returns nil (no error) when the URL is not a product page or
// the probe 404s — a non-Shopify site costs exactly one cheap GET. The probe is
// attempted whenever the path is /products/<handle>, regardless of detection.
func (p *Probe) Candidates(ctx context.Context, pageURL string) ([]extractors.Candidate, error) {
	parsed, err := url.Parse(pageURL)
	if err != nil {
		return nil, fmt.Errorf("parse shopify url: %w", err)
	}
	handle, ok := productHandle(parsed)
	if !ok {
		return nil, nil
	}

	jsonURL := &url.URL{Scheme: parsed.Scheme, Host: parsed.Host, Path: "/products/" + handle + ".json"}
	if err := scrapeapp.IsRedirectAllowed(ctx, p.resolver, jsonURL.String()); err != nil {
		return nil, err
	}

	base := &url.URL{Scheme: parsed.Scheme, Host: parsed.Host}
	if candidates := p.fetchAndParse(ctx, jsonURL.String(), false, base); len(candidates) > 0 {
		return candidates, nil
	}
	// .js fallback (prices in cents).
	jsURL := &url.URL{Scheme: parsed.Scheme, Host: parsed.Host, Path: "/products/" + handle + ".js"}
	if err := scrapeapp.IsRedirectAllowed(ctx, p.resolver, jsURL.String()); err != nil {
		return nil, err
	}
	return p.fetchAndParse(ctx, jsURL.String(), true, base), nil
}

func (p *Probe) fetchAndParse(ctx context.Context, rawURL string, fromJS bool, base *url.URL) []extractors.Candidate {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, http.NoBody)
	if err != nil {
		return nil
	}
	request.Header.Set("Accept", "application/json")
	// Reuse the shared Chrome UA rotation pool; a self-identifying WishizBot UA
	// gets 403'd by UA-blocking stores, forcing needs_review.
	request.Header.Set("User-Agent", httpfetch.RandomUserAgent())

	response, err := p.client.Do(request)
	if err != nil {
		return nil
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 2<<20))
	if err != nil {
		return nil
	}
	return parseProductJSON(body, fromJS, base)
}

// IsShopify reports whether the page exposes Shopify markers (headers / HTML).
// Used by the orchestrator to decide whether to probe non-/products/ URLs.
func IsShopify(html string, headers http.Header) bool {
	for key := range headers {
		if strings.HasPrefix(strings.ToLower(key), "x-shopify") {
			return true
		}
	}
	lower := strings.ToLower(html)
	return strings.Contains(lower, "cdn.shopify.com") ||
		strings.Contains(lower, "window.shopify") ||
		strings.Contains(lower, `name="shopify-`) ||
		strings.Contains(lower, "shopify-section")
}

// productHandle extracts the product handle from a Shopify-style path
// (/products/<handle> or /collections/<c>/products/<handle>).
func productHandle(u *url.URL) (string, bool) {
	segments := strings.Split(strings.Trim(u.Path, "/"), "/")
	for i := 0; i < len(segments)-1; i++ {
		if segments[i] == "products" && segments[i+1] != "" {
			handle := segments[i+1]
			handle = strings.TrimSuffix(handle, ".json")
			handle = strings.TrimSuffix(handle, ".js")
			return handle, true
		}
	}
	return "", false
}

type shopifyProduct struct {
	Product struct {
		Title string `json:"title"`
		Image struct {
			Src string `json:"src"`
		} `json:"image"`
		Images []struct {
			Src string `json:"src"`
		} `json:"images"`
		Variants []shopifyVariant `json:"variants"`
	} `json:"product"`
	// .js responses are flat (no "product" wrapper).
	Title         string           `json:"title"`
	FeaturedImage string           `json:"featured_image"`
	Images        []string         `json:"images"`
	Variants      []shopifyVariant `json:"variants"`
}

type shopifyVariant struct {
	Price             json.RawMessage `json:"price"`
	PresentmentPrices []struct {
		Price struct {
			Amount       string `json:"amount"`
			CurrencyCode string `json:"currency_code"`
		} `json:"price"`
	} `json:"presentment_prices"`
}

func parseProductJSON(data []byte, fromJS bool, base *url.URL) []extractors.Candidate {
	var parsed shopifyProduct
	if err := json.Unmarshal(data, &parsed); err != nil {
		return nil
	}

	title := parsed.Product.Title
	if title == "" {
		title = parsed.Title
	}
	image := firstImage(parsed, base)
	variants := parsed.Product.Variants
	if len(variants) == 0 {
		variants = parsed.Variants
	}
	if title == "" && len(variants) == 0 {
		return nil
	}

	var candidates []extractors.Candidate
	if title != "" {
		candidates = append(candidates, extractors.Candidate{
			Field: extractors.FieldName, Value: title, Source: extractors.SourceShopify, Raw: title,
		})
	}
	if image != "" {
		candidates = append(candidates, extractors.Candidate{
			Field: extractors.FieldImage, Value: image, Source: extractors.SourceShopify, Raw: image,
		})
	}
	if amount, currency, ok := variantPrice(variants, fromJS); ok {
		candidates = append(candidates, extractors.NewShopifyPriceCandidate(amount, currency))
	}
	return candidates
}

func firstImage(parsed shopifyProduct, base *url.URL) string {
	switch {
	case parsed.Product.Image.Src != "":
		return absolute(base, parsed.Product.Image.Src)
	case len(parsed.Product.Images) > 0:
		return absolute(base, parsed.Product.Images[0].Src)
	case parsed.FeaturedImage != "":
		return absolute(base, parsed.FeaturedImage)
	case len(parsed.Images) > 0:
		return absolute(base, parsed.Images[0])
	}
	return ""
}

// variantPrice returns the first variant's amount and currency. presentment_prices
// is the only path that carries a currency: its amount is already major-unit and
// is returned unscaled (a zero-decimal currency like JPY must not be divided by
// 100). The .json bare price is also major-unit, returned with an empty currency
// for downstream inference. The .js bare price is integer minor units with no
// currency — we can know neither the decimal exponent nor the label, so we skip
// it rather than emit a price we can't both scale and label.
func variantPrice(variants []shopifyVariant, fromJS bool) (amount string, currency string, ok bool) {
	if len(variants) == 0 {
		return "", "", false
	}
	variant := variants[0]
	if len(variant.PresentmentPrices) > 0 {
		presentment := variant.PresentmentPrices[0].Price
		if presentment.Amount != "" {
			return presentment.Amount, strings.ToUpper(presentment.CurrencyCode), true
		}
	}

	raw := strings.Trim(strings.TrimSpace(string(variant.Price)), `"`)
	if raw == "" {
		return "", "", false
	}
	if fromJS {
		// Integer minor units, no currency: skip (see doc comment).
		return "", "", false
	}
	return raw, "", true
}

func absolute(base *url.URL, candidate string) string {
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
