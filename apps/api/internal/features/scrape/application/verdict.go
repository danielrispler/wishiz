package application

import "fmt"

// ComputeVerdict applies the per-field trust gates to decide whether a product
// is safe to auto-complete. This is the kill-switch for "verify everything":
// auto_complete requires name + image + price all HIGH (price not in conflict)
// and currency HIGH-or-inferred-MEDIUM.
func ComputeVerdict(product Product) (verdict Verdict, reasons []string) {
	fields := product.Fields

	nameOK := fields.Name == ConfidenceHigh
	imageOK := fields.Image == ConfidenceHigh
	priceOK := fields.Price == ConfidenceHigh
	currencyOK := fields.Currency == ConfidenceHigh ||
		(fields.Currency == ConfidenceMedium && product.CurrencyInferred)

	if nameOK && imageOK && priceOK && currencyOK {
		return VerdictAutoComplete, nil
	}

	if !nameOK {
		reasons = append(reasons, reasonFor("name", fields.Name))
	}
	if !priceOK {
		reasons = append(reasons, reasonFor("price", fields.Price))
	}
	if !currencyOK {
		reasons = append(reasons, reasonFor("currency", fields.Currency))
	}
	if !imageOK {
		reasons = append(reasons, reasonFor("image", fields.Image))
	}

	if isReviewable(product) {
		return VerdictNeedsReview, reasons
	}
	return VerdictFailed, reasons
}

// isReviewable reports whether there is enough trustworthy partial data for a
// human to confirm: a name plus at least a price or an image.
func isReviewable(product Product) bool {
	nameAvailable := product.Fields.Name != ConfidenceMissing && product.Name != ""
	priceAvailable := product.Fields.Price != ConfidenceMissing && product.PriceAmount != ""
	imageAvailable := product.Fields.Image != ConfidenceMissing && product.ImageURL != ""
	return nameAvailable && (priceAvailable || imageAvailable)
}

func reasonFor(field string, confidence FieldConfidence) string {
	if confidence == "" {
		confidence = ConfidenceMissing
	}
	return fmt.Sprintf("%s_%s", field, confidence)
}
