package application

import (
	"strings"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

// isSeedable reports whether a scraped product is confident enough to persist to
// the discover feed. Discover only stores products the scraper is sure about:
// the verdict must be auto_complete (name+price at MEDIUM+ with a trusted
// currency — see scrape/application/verdict.go) AND there must be a usable name
// and image to render the card. needs_review/failed products are dropped, never
// surfaced for human review (discover is unattended ingestion).
func isSeedable(p scrapeapp.Product) bool {
	return p.Verdict == scrapeapp.VerdictAutoComplete &&
		strings.TrimSpace(p.Name) != "" &&
		strings.TrimSpace(p.ImageURL) != ""
}
