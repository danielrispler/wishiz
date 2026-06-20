package application

import (
	"context"
	"errors"
	"testing"
)

func TestNoopBackstopIsUnavailable(t *testing.T) {
	t.Parallel()

	chain := ResolverChain{Backstop: NewNoopBackstop()}
	candidates, err := chain.Backstop.Provide(context.Background(), FetchResult{})
	if !errors.Is(err, ErrBackstopUnavailable) {
		t.Fatalf("expected ErrBackstopUnavailable, got %v", err)
	}
	if candidates != nil {
		t.Fatalf("expected no candidates from noop backstop, got %v", candidates)
	}
}
