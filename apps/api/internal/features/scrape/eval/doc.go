// Package eval is the scraper scoring harness. It runs the consensus engine
// over saved HTML fixtures and measures per-field precision/recall, the
// auto_complete rate, and — the metric that matters most — the
// false-auto-complete rate (auto-completed with at least one wrong field),
// which must stay below 1%.
//
// It is build-tagged `eval` so it is excluded from the normal CI test run.
// Run it with:
//
//	go test -tags eval ./internal/features/scrape/eval/ -v
//
// Add real saved pages by dropping `<name>.html` into eval/testdata/ alongside a
// `<name>.json` expectation file (see Expectation), then list it in the manifest
// returned by loadCases. The bundled cases cover the structured-data-rich subset
// plus adversarial pages (Cloudflare challenge, 404, currency-less IL store) the
// engine must correctly abstain on.
package eval
