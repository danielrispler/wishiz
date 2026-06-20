package application

import "strings"

// antiBotBlockMaxLen bounds how large a body may be and still count as a block
// interstitial. Real product pages are tens of KB; Akamai/Cloudflare/Imperva
// deny pages are tiny. The cap keeps a real page that merely mentions a phrase
// from being misread as a hard block.
const antiBotBlockMaxLen = 6000

// antiBotBlockPhrases are body markers of a hard anti-bot interstitial.
var antiBotBlockPhrases = []string{
	"access denied",
	"reference #",
	"pardon our interruption",
	"are you a robot",
	"are you a human",
	"verify you are a human",
	"captcha",
	"request blocked",
	"attention required",            // Cloudflare
	"just a moment",                 // Cloudflare challenge
	"enable javascript and cookies", // Cloudflare challenge
	"unusual traffic",
}

// IsAntiBotBlock reports whether html is a hard anti-bot block page rather than a
// real product page: a small body carrying a known block phrase. Used to tell a
// genuine "this store blocks automated import" outcome apart from a transient,
// retryable scrape failure.
func IsAntiBotBlock(html string) bool {
	body := strings.TrimSpace(html)
	if body == "" || len(body) > antiBotBlockMaxLen {
		return false
	}
	lower := strings.ToLower(body)
	for _, phrase := range antiBotBlockPhrases {
		if strings.Contains(lower, phrase) {
			return true
		}
	}
	return false
}
