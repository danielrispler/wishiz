package application

import (
	"context"
	"errors"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application/extractors"
)

// ErrBackstopUnavailable is returned by the default no-op backstop. A real
// backstop returns nil + candidates (or a transport error) instead.
var ErrBackstopUnavailable = errors.New("scrape backstop unavailable")

// CandidateProvider is the pluggable seam for a future paid proxy / third-party
// scrape API / LLM extractor. It contributes candidates from an already-fetched
// page as "just another voter" — the consensus trust matrix would give it a low
// weight so it can corroborate but never auto-complete on its own. Slotting one
// in is pure main.go wiring: the engine, consensus and verdict are unchanged.
//
// (The Shopify probe is the first real CandidateSource; a backstop implements
// the same shape over a FetchResult.)
type CandidateProvider interface {
	Provide(ctx context.Context, result FetchResult) ([]extractors.Candidate, error)
}

// ResolverChain documents the intended fetch composition: try the cheap static
// fetch, then the headless render, then fall back to the paid backstop. It is a
// wiring placeholder — the live orchestrator runs Primary + Rendered (+ the
// Shopify probe) concurrently; Backstop stays a no-op until a paid layer is added.
type ResolverChain struct {
	Primary  Fetcher
	Rendered Fetcher
	Backstop CandidateProvider
}

// noopBackstop is the default backstop: always unavailable.
type noopBackstop struct{}

func (noopBackstop) Provide(context.Context, FetchResult) ([]extractors.Candidate, error) {
	return nil, ErrBackstopUnavailable
}

// NewNoopBackstop returns the default backstop that contributes nothing until a
// paid provider replaces it.
func NewNoopBackstop() CandidateProvider { return noopBackstop{} }
