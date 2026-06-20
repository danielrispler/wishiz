package extractors

import (
	"net/url"
	"testing"
)

func TestInferredCurrencyFromLocale(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.example/p")
	candidate, ok := InferredCurrency(parse(t, `<html lang="en-GB"><head></head><body></body></html>`), base, false)
	if !ok || candidate.Value != "GBP" || candidate.Source != SourceInferred || !candidate.Inferred {
		t.Fatalf("expected inferred GBP, got %+v ok=%v", candidate, ok)
	}
}

func TestInferredCurrencyFromTLD(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.co.il/p")
	candidate, ok := InferredCurrency(parse(t, `<html><head></head><body></body></html>`), base, false)
	if !ok || candidate.Value != "ILS" {
		t.Fatalf("expected inferred ILS, got %+v ok=%v", candidate, ok)
	}
}

func TestInferredCurrencyDotComOffByDefault(t *testing.T) {
	t.Parallel()

	base, _ := url.Parse("https://shop.com/p")
	if _, ok := InferredCurrency(parse(t, `<html><head></head><body></body></html>`), base, false); ok {
		t.Fatalf(".com must not infer USD by default")
	}
	candidate, ok := InferredCurrency(parse(t, `<html><head></head><body></body></html>`), base, true)
	if !ok || candidate.Value != "USD" {
		t.Fatalf("expected opt-in .com -> USD, got %+v ok=%v", candidate, ok)
	}
}
