package application

import "testing"

func TestValidateName(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		host string
		want bool
	}{
		{"Desk Lamp", "shop.example", true},
		{"Just a moment...", "shop.example", false},
		{"Attention Required! | Cloudflare", "shop.example", false},
		{"shop.example", "shop.example", false},
		{"shop", "shop.example", false},
		{"", "shop.example", false},
		{"Access Denied", "x.com", false},
	}
	for _, tc := range cases {
		if got := ValidateName(tc.name, tc.host); got != tc.want {
			t.Errorf("ValidateName(%q,%q)=%v want %v", tc.name, tc.host, got, tc.want)
		}
	}
}

func TestValidateImageURL(t *testing.T) {
	t.Parallel()

	cases := map[string]bool{
		"https://cdn.example/product.jpg":     true,
		"http://cdn.example/p.png":            true,
		"https://cdn.example/brand-logo.svg":  false,
		"https://cdn.example/sprite.png":      false,
		"https://cdn.example/placeholder.gif": false,
		"data:image/png;base64,AAAA":          false,
		"/relative/path.jpg":                  false,
		"":                                    false,

		// A marker appearing only as a substring of the HOST or of a non-marker
		// filename must NOT reject the image (segment-boundary, not Contains).
		"https://silicon-power.com/products/charger.jpg": true,
		"https://logitech.com/mouse.jpg":                 true,
		"https://iconicbrand.com/p/widget.jpg":           true,
		"https://cdn.example/products/silicon-case.jpg":  true,

		// Real non-product assets still reject on a whole-segment match.
		"https://cdn.example/logo.png":     false,
		"https://cdn.example/favicon.ico":  false,
		"https://cdn.example/icons/ic.png": true, // filename "ic.png" is not a marker
		"https://cdn.example/icon-512.png": false,
	}
	for url, want := range cases {
		if got := ValidateImageURL(url); got != want {
			t.Errorf("ValidateImageURL(%q)=%v want %v", url, got, want)
		}
	}
}

func TestValidatePrice(t *testing.T) {
	t.Parallel()

	cases := []struct {
		amount string
		want   bool
	}{
		{"40.00", true},
		{"1,299.99", true},
		{"0", false},
		{"-5", false},
		{"99999999", false},
		{"abc", false},
	}
	for _, tc := range cases {
		if got := ValidatePrice(tc.amount, 0); got != tc.want {
			t.Errorf("ValidatePrice(%q)=%v want %v", tc.amount, got, tc.want)
		}
	}
}

func TestCleanLink(t *testing.T) {
	t.Parallel()

	cases := map[string]string{
		"https://s.example/p?utm_source=x&id=5&gclid=z": "https://s.example/p?id=5",
		"https://s.example/p?fbclid=abc":                "https://s.example/p",
		"https://s.example/p#frag":                      "https://s.example/p",
		"https://s.example/p":                           "https://s.example/p",
	}
	for raw, want := range cases {
		if got := CleanLink(raw); got != want {
			t.Errorf("CleanLink(%q)=%q want %q", raw, got, want)
		}
	}
}

func TestParseECBRatesToleratesMissingSupportedCodes(t *testing.T) {
	t.Parallel()

	// Feed lists only EUR base + USD; the other supported codes are absent. With
	// the softened invariant this must succeed (not error), keeping rates fresh.
	payload := []byte(`<gesmes:Envelope><Cube><Cube time="2026-06-20">
		<Cube currency="USD" rate="1.08"/></Cube></Cube></gesmes:Envelope>`)
	rates, err := parseECBRates(payload)
	if err != nil {
		t.Fatalf("expected tolerant parse, got %v", err)
	}
	if rates["EUR"] != 1 || rates["USD"] != 1.08 {
		t.Fatalf("unexpected rates: %+v", rates)
	}
	if _, ok := rates["CZK"]; ok {
		t.Fatalf("did not expect CZK in a feed that omits it")
	}
}
