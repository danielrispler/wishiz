package application

import "fmt"

// ComputeVerdict applies the per-field trust gates to decide whether a product
// is safe to auto-complete. Calibration (relaxed): auto_complete requires a
// name and price of at least MEDIUM confidence (price NOT in conflict and NOT
// LOW/MISSING) and currency HIGH-or-inferred-MEDIUM. Image is display-only and
// does NOT gate — a missing/low image still auto-completes. A genuine
// disagreement between sources (ConfidenceConflict) is excluded by the
// HIGH/MEDIUM membership test and still routes to review.
func ComputeVerdict(product Product) (verdict Verdict, reasons []string) {
	fields := product.Fields

	nameOK := fields.Name == ConfidenceHigh || fields.Name == ConfidenceMedium
	priceOK := fields.Price == ConfidenceHigh || fields.Price == ConfidenceMedium
	currencyOK := fields.Currency == ConfidenceHigh ||
		(fields.Currency == ConfidenceMedium && product.CurrencyInferred)

	if nameOK && priceOK && currencyOK {
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

// verdictRank orders verdicts so the ZenRows backstop second pass can only RAISE
// or HOLD the verdict, never lower it: a re-reconcile that would degrade the
// outcome is discarded (see ScrapeImport). auto_complete > needs_review > failed.
//
// Given append-only candidates (the backstop adds evidence; a consensus conflict
// keeps the field value, only flagging confidence) the discard branch is not
// reachable through current extraction — this is a defensive invariant that holds
// even if consensus later changes to drop conflicted values.
func verdictRank(v Verdict) int {
	switch v {
	case VerdictAutoComplete:
		return 2
	case VerdictNeedsReview:
		return 1
	default: // VerdictFailed
		return 0
	}
}

func reasonFor(field string, confidence FieldConfidence) string {
	if confidence == "" {
		confidence = ConfidenceMissing
	}
	return fmt.Sprintf("%s_%s", field, confidence)
}
