package headless

import "testing"

func TestHTMLHasProductSignal(t *testing.T) {
	t.Parallel()

	withSignal := map[string]string{
		"jsonld product":    `<script type="application/ld+json">{"@type":"Product","name":"X"}</script>`,
		"og price amount":   `<meta property="product:price:amount" content="799">`,
		"og price legacy":   `<meta property="og:price:amount" content="49.99">`,
		"microdata product": `<div itemscope itemtype="https://schema.org/Product"><span itemprop="price">10</span></div>`,
	}
	for name, html := range withSignal {
		if !htmlHasProductSignal(html) {
			t.Errorf("%s: expected product signal", name)
		}
	}

	// A shell page that has only generic OpenGraph (title/image) or nothing is NOT
	// yet a settled product — the render must keep waiting for hydration.
	without := map[string]string{
		"bare shell":     `<html><head><title>Loading…</title></head><body></body></html>`,
		"og title+image": `<meta property="og:title" content="Home"><meta property="og:image" content="/logo.png">`,
		"access denied":  `<html><head><title>Access Denied</title></head><body>reference #</body></html>`,
	}
	for name, html := range without {
		if htmlHasProductSignal(html) {
			t.Errorf("%s: should NOT be treated as a product signal", name)
		}
	}
}
