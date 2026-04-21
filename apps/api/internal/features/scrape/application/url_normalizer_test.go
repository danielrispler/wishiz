package application

import (
	"context"
	"testing"
)

func TestNormalizeProductURLUnwrapsGoogleDestination(t *testing.T) {
	t.Parallel()

	normalized, err := NormalizeProductURL(
		context.Background(),
		stubResolver{},
		"https://www.google.co.il/url?sa=t&url=https%3A%2F%2Fwww.nike.com%2Fil%2Fproduct",
	)
	if err != nil {
		t.Fatalf("normalize product url: %v", err)
	}
	if normalized.String() != "https://www.nike.com/il/product" {
		t.Fatalf("unexpected normalized URL %q", normalized.String())
	}
}

func TestNormalizeProductURLRejectsUnsafeGoogleDestination(t *testing.T) {
	t.Parallel()

	_, err := NormalizeProductURL(
		context.Background(),
		stubResolver{},
		"https://www.google.com/url?q=http%3A%2F%2F127.0.0.1%2Fprivate",
	)
	if err == nil {
		t.Fatalf("expected validation error")
	}
}
