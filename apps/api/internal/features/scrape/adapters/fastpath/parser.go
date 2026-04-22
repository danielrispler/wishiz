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
	priceCandidates := priceCandidatesFromProduct(product)

	var candidates []priceCandidate
	product, candidates = fillFromJSONLD(product, document)
	priceCandidates = append(priceCandidates, candidates...)
	product, candidates = fillFromMeta(product, document)
	priceCandidates = append(priceCandidates, candidates...)
	product, candidates = fillFromGenericDOM(product, document)
	priceCandidates = append(priceCandidates, candidates...)

	product.Name = normalizeText(product.Name)
	product.ImageURL = resolveURL(parsedURL, product.ImageURL)
	product = applyBestPrice(product, priceCandidates)

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
			Name:            firstNonEmpty(textOf(document, "h1"), metaContent(document, "og:title", "property")),
			ImageURL:        firstSource(document, `[data-qa-action="product-slide"] img`, "src", "srcset", "data-src"),
			PriceAmount:     amountFromText(textOf(document, "span.price__amount")),
			PriceCurrency:   currencyFromText(textOf(document, "span.price__amount")),
			PriceConfidence: scrapeapp.PriceConfidenceHigh,
			PriceSource:     scrapeapp.PriceSourceMerchantSelector,
			PriceRawText:    textOf(document, "span.price__amount"),
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
			PriceAmount:     amountFromText(priceText),
			PriceCurrency:   currencyFromText(priceText),
			PriceConfidence: scrapeapp.PriceConfidenceHigh,
			PriceSource:     scrapeapp.PriceSourceMerchantSelector,
			PriceRawText:    priceText,
		}
	case "uniqlo":
		priceText := textOf(document, ".price-box")
		return scrapeapp.Product{
			Name:            textOf(document, "h1"),
			ImageURL:        firstSource(document, "picture source", "srcset", "src"),
			PriceAmount:     amountFromText(priceText),
			PriceCurrency:   currencyFromText(priceText),
			PriceConfidence: scrapeapp.PriceConfidenceHigh,
			PriceSource:     scrapeapp.PriceSourceMerchantSelector,
			PriceRawText:    priceText,
		}
	case "nike":
		priceText := textOf(document, `[data-test="product-price"]`)
		return scrapeapp.Product{
			Name:            textOf(document, `h1#pdp_product_title`),
			ImageURL:        firstSource(document, `[data-test="hero-image"] img`, "src", "srcset"),
			PriceAmount:     amountFromText(priceText),
			PriceCurrency:   currencyFromText(priceText),
			PriceConfidence: scrapeapp.PriceConfidenceHigh,
			PriceSource:     scrapeapp.PriceSourceMerchantSelector,
			PriceRawText:    priceText,
		}
	default:
		return scrapeapp.Product{}
	}
}

func fillFromJSONLD(product scrapeapp.Product, document *goquery.Document) (scrapeapp.Product, []priceCandidate) {
	var candidates []priceCandidate
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

			candidates = append(candidates, readOfferPrices(node["offers"])...)

			if product.IsComplete() {
				return false
			}
		}

		return true
	})

	return product, candidates
}

func fillFromMeta(product scrapeapp.Product, document *goquery.Document) (scrapeapp.Product, []priceCandidate) {
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

	var candidates []priceCandidate
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
		raw := strings.TrimSpace(strings.TrimSpace(priceCurrency) + " " + priceText)
		candidates = append(candidates, newPriceCandidate(raw, scrapeapp.PriceSourceMeta, scrapeapp.PriceConfidenceHigh, raw))
	}

	return product, candidates
}

func fillFromGenericDOM(product scrapeapp.Product, document *goquery.Document) (scrapeapp.Product, []priceCandidate) {
	product.Name = firstNonEmpty(product.Name, textOf(document, "h1"))
	product.ImageURL = firstNonEmpty(product.ImageURL, firstSource(document, "img", "src", "srcset", "data-src"))

	var candidates []priceCandidate
	candidates = append(candidates, selectorPriceCandidates(document, `[itemprop="price"]`, scrapeapp.PriceSourceSelector, scrapeapp.PriceConfidenceMedium)...)
	candidates = append(candidates, selectorPriceCandidates(document, ".current-price", scrapeapp.PriceSourceSelector, scrapeapp.PriceConfidenceMedium)...)
	candidates = append(candidates, selectorPriceCandidates(document, ".sale-price", scrapeapp.PriceSourceSelector, scrapeapp.PriceConfidenceMedium)...)
	candidates = append(candidates, selectorPriceCandidates(document, ".price-current", scrapeapp.PriceSourceSelector, scrapeapp.PriceConfidenceMedium)...)
	candidates = append(candidates, selectorPriceCandidates(document, ".price__current", scrapeapp.PriceSourceSelector, scrapeapp.PriceConfidenceMedium)...)
	candidates = append(candidates, selectorPriceCandidates(document, ".price", scrapeapp.PriceSourceGenericDOM, scrapeapp.PriceConfidenceLow)...)
	candidates = append(candidates, selectorPriceCandidates(document, ".product-price", scrapeapp.PriceSourceGenericDOM, scrapeapp.PriceConfidenceLow)...)

	return product, candidates
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

type priceCandidate struct {
	amount     string
	currency   string
	raw        string
	source     string
	confidence string
	warnings   []string
}

func priceCandidatesFromProduct(product scrapeapp.Product) []priceCandidate {
	if product.PriceAmount == "" || product.PriceCurrency == "" {
		return nil
	}
	return []priceCandidate{{
		amount:     product.PriceAmount,
		currency:   product.PriceCurrency,
		raw:        product.PriceRawText,
		source:     product.PriceSource,
		confidence: product.PriceConfidence,
		warnings:   product.PriceWarnings,
	}}
}

func selectorPriceCandidates(document *goquery.Document, selector string, source string, confidence string) []priceCandidate {
	var candidates []priceCandidate
	document.Find(selector).Each(func(_ int, selection *goquery.Selection) {
		raw := firstNonEmpty(
			attributeValue(selection, "content"),
			attributeValue(selection, "data-price"),
			attributeValue(selection, "aria-label"),
			selection.Text(),
		)
		if raw == "" {
			return
		}
		context := normalizeText(strings.Join([]string{
			attributeValue(selection, "class"),
			attributeValue(selection, "id"),
			raw,
		}, " "))
		candidates = append(candidates, newPriceCandidate(raw, source, confidence, context))
	})
	return candidates
}

func attributeValue(selection *goquery.Selection, name string) string {
	value, _ := selection.Attr(name)
	return value
}

func newPriceCandidate(raw string, source string, confidence string, context string) priceCandidate {
	amount, currency, ok := scrapeapp.NormalizePrice(raw)
	candidate := priceCandidate{
		raw:        normalizeText(raw),
		source:     source,
		confidence: confidence,
	}
	if ok {
		candidate.amount = amount
		candidate.currency = currency
	}
	if candidate.currency == "" {
		candidate.warnings = append(candidate.warnings, scrapeapp.PriceWarningMissingCurrency)
		candidate.confidence = scrapeapp.PriceConfidenceSuspicious
	}
	if confidence == scrapeapp.PriceConfidenceLow {
		candidate.warnings = append(candidate.warnings, scrapeapp.PriceWarningLowTrustSource)
	}
	if looksLikeNonPrimaryPrice(context) {
		candidate.warnings = append(candidate.warnings, scrapeapp.PriceWarningNonPrimaryContext)
		candidate.confidence = scrapeapp.PriceConfidenceSuspicious
	}
	return candidate
}

func applyBestPrice(product scrapeapp.Product, candidates []priceCandidate) scrapeapp.Product {
	candidates = usablePriceCandidates(candidates)
	if len(candidates) == 0 {
		product.PriceAmount = ""
		product.PriceCurrency = ""
		product.PriceConfidence = ""
		product.PriceSource = ""
		product.PriceRawText = ""
		product.PriceWarnings = nil
		return product
	}

	best := candidates[0]
	for _, candidate := range candidates[1:] {
		if confidenceRank(candidate.confidence) > confidenceRank(best.confidence) {
			best = candidate
		}
	}

	warnings := append([]string{}, best.warnings...)
	if hasConflictingTrustedCandidates(candidates) {
		best.confidence = scrapeapp.PriceConfidenceSuspicious
		warnings = append(warnings, scrapeapp.PriceWarningConflictingCandidates)
	}

	product.PriceAmount = best.amount
	product.PriceCurrency = best.currency
	product.PriceConfidence = best.confidence
	product.PriceSource = best.source
	product.PriceRawText = best.raw
	product.PriceWarnings = uniqueStrings(warnings)
	return product
}

func usablePriceCandidates(candidates []priceCandidate) []priceCandidate {
	var usable []priceCandidate
	for _, candidate := range candidates {
		if candidate.amount == "" || candidate.currency == "" {
			continue
		}
		if candidate.confidence == "" {
			candidate.confidence = scrapeapp.PriceConfidenceLow
		}
		usable = append(usable, candidate)
	}
	return usable
}

func confidenceRank(confidence string) int {
	switch confidence {
	case scrapeapp.PriceConfidenceHigh:
		return 4
	case scrapeapp.PriceConfidenceMedium:
		return 3
	case scrapeapp.PriceConfidenceLow:
		return 2
	case scrapeapp.PriceConfidenceSuspicious:
		return 1
	default:
		return 0
	}
}

func hasConflictingTrustedCandidates(candidates []priceCandidate) bool {
	var trusted []priceCandidate
	for _, candidate := range candidates {
		if candidate.confidence == scrapeapp.PriceConfidenceHigh || candidate.confidence == scrapeapp.PriceConfidenceMedium {
			trusted = append(trusted, candidate)
		}
	}
	for i := 0; i < len(trusted); i++ {
		for j := i + 1; j < len(trusted); j++ {
			if trusted[i].amount != trusted[j].amount || trusted[i].currency != trusted[j].currency {
				return true
			}
		}
	}
	return false
}

func looksLikeNonPrimaryPrice(context string) bool {
	normalized := strings.ToLower(context)
	return strings.Contains(normalized, "compare") ||
		strings.Contains(normalized, "was ") ||
		strings.Contains(normalized, "list price") ||
		strings.Contains(normalized, "save ") ||
		strings.Contains(normalized, "installment") ||
		strings.Contains(normalized, "finance") ||
		strings.Contains(normalized, "shipping") ||
		strings.Contains(normalized, "per month") ||
		strings.Contains(normalized, "monthly")
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	var result []string
	for _, value := range values {
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		result = append(result, value)
	}
	return result
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

func readOfferPrices(value any) []priceCandidate {
	switch typed := value.(type) {
	case map[string]any:
		amount := stringValue(typed["price"])
		currency := stringValue(typed["priceCurrency"])
		if amount != "" {
			raw := strings.TrimSpace(strings.TrimSpace(currency) + " " + amount)
			context := firstNonEmpty(stringValue(typed["name"]), raw)
			return []priceCandidate{newPriceCandidate(raw, scrapeapp.PriceSourceJSONLD, scrapeapp.PriceConfidenceHigh, context)}
		}
		return nil
	case []any:
		var candidates []priceCandidate
		for _, entry := range typed {
			if offer, ok := entry.(map[string]any); ok {
				candidates = append(candidates, readOfferPrices(offer)...)
			}
		}
		return candidates
	}

	return nil
}
