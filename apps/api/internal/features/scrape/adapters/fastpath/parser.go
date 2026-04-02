package fastpath

import (
	"encoding/json"
	"net/url"
	"regexp"
	"strings"

	"github.com/PuerkitoBio/goquery"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

func ExtractProduct(pageURL string, html string) (scrapeapp.Product, error) {
	document, err := goquery.NewDocumentFromReader(strings.NewReader(html))
	if err != nil {
		return scrapeapp.Product{}, err
	}

	parsedURL, err := url.Parse(pageURL)
	if err != nil {
		return scrapeapp.Product{}, err
	}

	merchant := detectMerchant(parsedURL.Hostname())

	product := extractMerchantProduct(document, merchant)
	product = fillFromJSONLD(product, document)
	product = fillFromMeta(product, document)
	product = fillFromGenericDOM(product, document)

	product.Name = normalizeText(product.Name)
	product.ImageURL = resolveURL(parsedURL, product.ImageURL)

	return product, nil
}

func detectMerchant(host string) string {
	normalized := strings.ToLower(host)
	switch {
	case strings.Contains(normalized, "zara.com"):
		return "zara"
	case strings.Contains(normalized, "hm.com"):
		return "hm"
	case strings.Contains(normalized, "uniqlo.com"):
		return "uniqlo"
	case strings.Contains(normalized, "nike.com"):
		return "nike"
	default:
		return ""
	}
}

func extractMerchantProduct(document *goquery.Document, merchant string) scrapeapp.Product {
	switch merchant {
	case "zara":
		return scrapeapp.Product{
			Name:          firstNonEmpty(textOf(document, "h1"), metaContent(document, "og:title", "property")),
			ImageURL:      firstSource(document, `[data-qa-action="product-slide"] img`, "src", "srcset", "data-src"),
			PriceAmount:   amountFromText(textOf(document, "span.price__amount")),
			PriceCurrency: currencyFromText(textOf(document, "span.price__amount")),
		}
	case "hm":
		priceText := firstNonEmpty(
			textOf(document, `[data-testid="formatted-value"]`),
			textOf(document, `[data-testid="product-price"]`),
			textOf(document, ".price-value"),
			textOf(document, `[class*="price"]`),
		)
		return scrapeapp.Product{
			Name: firstNonEmpty(
				textOf(document, "h1"),
				metaContent(document, "og:title", "property"),
			),
			ImageURL: firstNonEmpty(
				firstSource(document, `picture source`, "srcset", "src"),
				firstSource(document, `.product-detail-main-image img`, "src", "srcset", "data-src"),
				firstSource(document, `[class*="product"] img`, "src", "srcset", "data-src"),
			),
			PriceAmount:   amountFromText(priceText),
			PriceCurrency: currencyFromText(priceText),
		}
	case "uniqlo":
		return scrapeapp.Product{
			Name:          textOf(document, "h1"),
			ImageURL:      firstSource(document, "picture source", "srcset", "src"),
			PriceAmount:   amountFromText(textOf(document, ".price-box")),
			PriceCurrency: currencyFromText(textOf(document, ".price-box")),
		}
	case "nike":
		return scrapeapp.Product{
			Name:          textOf(document, `h1#pdp_product_title`),
			ImageURL:      firstSource(document, `[data-test="hero-image"] img`, "src", "srcset"),
			PriceAmount:   amountFromText(textOf(document, `[data-test="product-price"]`)),
			PriceCurrency: currencyFromText(textOf(document, `[data-test="product-price"]`)),
		}
	default:
		return scrapeapp.Product{}
	}
}

func fillFromJSONLD(product scrapeapp.Product, document *goquery.Document) scrapeapp.Product {
	document.Find(`script[type="application/ld+json"]`).EachWithBreak(func(_ int, selection *goquery.Selection) bool {
		payload := strings.TrimSpace(selection.Text())
		if payload == "" {
			return true
		}

		var decoded any
		if err := json.Unmarshal([]byte(payload), &decoded); err != nil {
			return true
		}

		for _, node := range flattenJSONMaps(decoded) {
			if !isProductNode(node) {
				continue
			}

			product.Name = firstNonEmpty(product.Name, stringValue(node["name"]))
			product.ImageURL = firstNonEmpty(product.ImageURL, readImage(node["image"]))

			if product.PriceAmount == "" || product.PriceCurrency == "" {
				amount, currency := readOfferPrice(node["offers"])
				product.PriceAmount = firstNonEmpty(product.PriceAmount, amount)
				product.PriceCurrency = firstNonEmpty(product.PriceCurrency, currency)
			}

			if product.IsComplete() {
				return false
			}
		}

		return true
	})

	return product
}

func fillFromMeta(product scrapeapp.Product, document *goquery.Document) scrapeapp.Product {
	product.Name = firstNonEmpty(
		product.Name,
		metaContent(document, "og:title", "property"),
		metaContent(document, "twitter:title", "name"),
		document.Find("title").First().Text(),
	)

	product.ImageURL = firstNonEmpty(
		product.ImageURL,
		metaContent(document, "og:image", "property"),
		metaContent(document, "twitter:image", "name"),
		metaContent(document, "image", "name"),
	)

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
		amount, currency, ok := scrapeapp.NormalizePrice(priceText)
		if ok {
			product.PriceAmount = firstNonEmpty(product.PriceAmount, amount)
			product.PriceCurrency = firstNonEmpty(product.PriceCurrency, firstNonEmpty(priceCurrency, currency))
		}
	}

	return product
}

func fillFromGenericDOM(product scrapeapp.Product, document *goquery.Document) scrapeapp.Product {
	product.Name = firstNonEmpty(product.Name, textOf(document, "h1"))
	product.ImageURL = firstNonEmpty(product.ImageURL, firstSource(document, "img", "src", "srcset", "data-src"))

	if product.PriceAmount == "" || product.PriceCurrency == "" {
		priceText := firstNonEmpty(
			textOf(document, `[itemprop="price"]`),
			textOf(document, ".price"),
			textOf(document, ".product-price"),
		)
		amount, currency, ok := scrapeapp.NormalizePrice(priceText)
		if ok {
			product.PriceAmount = firstNonEmpty(product.PriceAmount, amount)
			product.PriceCurrency = firstNonEmpty(product.PriceCurrency, currency)
		}
	}

	return product
}

func normalizeText(value string) string {
	trimmed := strings.TrimSpace(value)
	return whitespacePattern.ReplaceAllString(trimmed, " ")
}

var whitespacePattern = regexp.MustCompile(`\s+`)

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		normalized := normalizeText(value)
		if normalized != "" {
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

func firstSource(document *goquery.Document, selector string, attributes ...string) string {
	var resolved string
	document.Find(selector).EachWithBreak(func(_ int, selection *goquery.Selection) bool {
		for _, attribute := range attributes {
			value, ok := selection.Attr(attribute)
			if !ok {
				continue
			}
			candidate := parseSourceValue(value)
			if candidate == "" {
				continue
			}
			if strings.Contains(strings.ToLower(candidate), "logo") ||
				strings.Contains(strings.ToLower(candidate), "icon") ||
				strings.Contains(strings.ToLower(candidate), "placeholder") {
				continue
			}
			resolved = candidate
			return false
		}
		return true
	})
	return resolved
}

func parseSourceValue(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}

	if strings.Contains(trimmed, ",") {
		firstCandidate := strings.TrimSpace(strings.Split(trimmed, ",")[0])
		firstField := strings.Fields(firstCandidate)
		if len(firstField) > 0 {
			return firstField[0]
		}
	}

	fields := strings.Fields(trimmed)
	if len(fields) > 0 {
		return fields[0]
	}

	return trimmed
}

func resolveURL(pageURL *url.URL, candidate string) string {
	if candidate == "" {
		return ""
	}

	parsed, err := url.Parse(candidate)
	if err != nil {
		return candidate
	}
	return pageURL.ResolveReference(parsed).String()
}

func amountFromText(value string) string {
	amount, _, ok := scrapeapp.NormalizePrice(value)
	if !ok {
		return ""
	}
	return amount
}

func currencyFromText(value string) string {
	_, currency, ok := scrapeapp.NormalizePrice(value)
	if !ok {
		return ""
	}
	return currency
}

func flattenJSONMaps(value any) []map[string]any {
	switch typed := value.(type) {
	case map[string]any:
		result := []map[string]any{typed}
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
	typeValue := node["@type"]
	switch typed := typeValue.(type) {
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
	text, _ := value.(string)
	return normalizeText(text)
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

func readOfferPrice(value any) (string, string) {
	switch typed := value.(type) {
	case map[string]any:
		amount := stringValue(typed["price"])
		currency := stringValue(typed["priceCurrency"])
		if amount != "" && currency != "" {
			if normalizedAmount, normalizedCurrency, ok := scrapeapp.NormalizePrice(currency + " " + amount); ok {
				return normalizedAmount, normalizedCurrency
			}
			return amount, currency
		}
		if amount != "" {
			if normalizedAmount, normalizedCurrency, ok := scrapeapp.NormalizePrice(amount); ok {
				return normalizedAmount, normalizedCurrency
			}
		}
	case []any:
		for _, entry := range typed {
			if offer, ok := entry.(map[string]any); ok {
				amount, currency := readOfferPrice(offer)
				if amount != "" && currency != "" {
					return amount, currency
				}
			}
		}
	}

	return "", ""
}
