package extractors

import (
	"net/url"
	"testing"
)

func mustBase(t *testing.T, raw string) *url.URL {
	t.Helper()
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("parse base %q: %v", raw, err)
	}
	return u
}

func candidateFor(candidates []Candidate, field Field) (Candidate, bool) {
	for _, c := range candidates {
		if c.Field == field {
			return c, true
		}
	}
	return Candidate{}, false
}

// Redken-shape: a modest discount (23.80 of 34.00 ≈ 70%) → trusted price.
const redkenAutoparseJSON = `{
	"title": "Redken Acidic Bonding Concentrate Shampoo",
	"price": "$23.80",
	"price_without_discount": "$34.00",
	"discount": "-30%",
	"images": ["https://m.media-amazon.com/images/I/redken.jpg"]
}`

func TestMapAutoparseProductTrustsModestDiscount(t *testing.T) {
	t.Parallel()

	got := MapAutoparseProduct([]byte(redkenAutoparseJSON), "amazon.com", mustBase(t, "https://www.amazon.com/dp/B0B64RSCCV"))

	name, ok := candidateFor(got, FieldName)
	if !ok || name.Value != "Redken Acidic Bonding Concentrate Shampoo" {
		t.Fatalf("name candidate = %+v, ok=%v", name, ok)
	}
	if name.Source != SourceZenRowsAutoparse {
		t.Fatalf("name source = %q, want %q", name.Source, SourceZenRowsAutoparse)
	}

	image, ok := candidateFor(got, FieldImage)
	if !ok || image.Value != "https://m.media-amazon.com/images/I/redken.jpg" {
		t.Fatalf("image candidate = %+v, ok=%v", image, ok)
	}

	price, ok := candidateFor(got, FieldPrice)
	if !ok {
		t.Fatalf("expected a price candidate, got none: %+v", got)
	}
	if price.Value != "23.80" || price.Currency != "USD" {
		t.Fatalf("price candidate = {value:%q currency:%q}, want {23.80 USD}", price.Value, price.Currency)
	}
	if price.Inferred {
		t.Fatal("price currency must be explicit (resolved host), not inferred")
	}
	if price.Source != SourceZenRowsAutoparse {
		t.Fatalf("price source = %q, want %q", price.Source, SourceZenRowsAutoparse)
	}
}

// Bose-shape: autoparse price (26.99) is ~10% of price_without_discount (269) —
// an internally inconsistent value, so the price is dropped and the import falls
// to needs_review, but the (trustworthy) name + image are still surfaced.
const boseAutoparseJSON = `{
	"title": "Bose QuietComfort Ultra Headphones",
	"price": "$26.99",
	"price_without_discount": "$269.00",
	"discount": "-33%",
	"images": ["https://m.media-amazon.com/images/I/bose.jpg"]
}`

func TestMapAutoparseProductDropsSuspiciousPrice(t *testing.T) {
	t.Parallel()

	got := MapAutoparseProduct([]byte(boseAutoparseJSON), "amazon.com", mustBase(t, "https://www.amazon.com/dp/B0GL8FBD85"))

	if _, ok := candidateFor(got, FieldPrice); ok {
		t.Fatal("expected NO price candidate for a deeply discounted autoparse price")
	}
	if name, ok := candidateFor(got, FieldName); !ok || name.Value != "Bose QuietComfort Ultra Headphones" {
		t.Fatalf("name candidate should survive, got %+v ok=%v", name, ok)
	}
	if _, ok := candidateFor(got, FieldImage); !ok {
		t.Fatal("image candidate should survive a dropped price")
	}
}

func TestMapAutoparseProductCurrencyByMarketplace(t *testing.T) {
	t.Parallel()
	cases := []struct {
		host string
		want string // "" means no currency must be assigned
	}{
		{"amazon.com", "USD"},
		{"amazon.co.uk", "GBP"},
		{"amazon.de", "EUR"},
		{"amazon.co.jp", "JPY"},
		{"www.amazon.com", "USD"},
		{"smile.amazon.de", "EUR"},
		{"amazon.unknown", ""}, // unknown marketplace → no guessed currency
		{"a.co", ""},           // a shortener is never a final/resolved host
	}
	for _, tc := range cases {
		got := MapAutoparseProduct([]byte(redkenAutoparseJSON), tc.host, nil)
		price, ok := candidateFor(got, FieldPrice)
		if !ok {
			t.Fatalf("%s: expected a price candidate", tc.host)
		}
		if price.Currency != tc.want {
			t.Errorf("%s: currency = %q, want %q", tc.host, price.Currency, tc.want)
		}
	}
}

func TestMapAutoparseProductEdgeCases(t *testing.T) {
	t.Parallel()

	if got := MapAutoparseProduct([]byte("not json"), "amazon.com", nil); got != nil {
		t.Fatalf("garbage JSON must map to nil, got %+v", got)
	}

	noPrice := `{"title":"Thing","price":"","price_without_discount":"$10","images":["https://x/i.jpg"]}`
	got := MapAutoparseProduct([]byte(noPrice), "amazon.com", nil)
	if _, ok := candidateFor(got, FieldPrice); ok {
		t.Fatal("unparseable price must not emit a price candidate")
	}
	if _, ok := candidateFor(got, FieldName); !ok {
		t.Fatal("name should still be emitted when price is absent")
	}

	// price_without_discount must never leak out as the price.
	for _, c := range got {
		if c.Field == FieldPrice {
			t.Fatal("price_without_discount must never become a price candidate")
		}
	}
}

func TestIsAmazonHost(t *testing.T) {
	t.Parallel()
	cases := []struct {
		host string
		want bool
	}{
		{"amazon.com", true},
		{"www.amazon.com", true},
		{"smile.amazon.de", true},
		{"amazon.co.jp", true},
		{"a.co", true},
		{"amzn.to", true},
		{"amzn.eu", true},
		{"amzn.asia", true},
		{"amzn.com", true},
		{"amazonaws.com", false},
		{"notamazon.com", false},
		{"shop.example", false},
		{"", false},
	}
	for _, tc := range cases {
		if got := IsAmazonHost(tc.host); got != tc.want {
			t.Errorf("IsAmazonHost(%q) = %v, want %v", tc.host, got, tc.want)
		}
	}
}
