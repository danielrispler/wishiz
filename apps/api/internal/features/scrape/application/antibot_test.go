package application

import (
	"strings"
	"testing"
)

func TestIsAntiBotBlock(t *testing.T) {
	t.Parallel()

	blocks := map[string]string{
		"akamai access denied": `<html><head><title>Access Denied</title></head><body>You don't have permission. Reference #18.abc</body></html>`,
		"cloudflare moment":    `<html><body><h1>Just a moment...</h1><p>Enable JavaScript and cookies to continue</p></body></html>`,
		"captcha wall":         `<html><body>Please complete the CAPTCHA to continue</body></html>`,
		"attention required":   `<html><title>Attention Required! | Cloudflare</title></html>`,
	}
	for name, html := range blocks {
		if !IsAntiBotBlock(html) {
			t.Errorf("%s: expected anti-bot block", name)
		}
	}

	notBlocks := map[string]string{
		"empty":   "",
		"product": autoCompleteHTML,
		// A large, real page that merely mentions a word is not a block page.
		"large mention": "<html><body>" + strings.Repeat("real product copy ", 1000) +
			" our return policy: access denied for fraud.</body></html>",
	}
	for name, html := range notBlocks {
		if IsAntiBotBlock(html) {
			t.Errorf("%s: should NOT be treated as an anti-bot block", name)
		}
	}
}
