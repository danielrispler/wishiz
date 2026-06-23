package application

// ProgressReporter receives coarse progress updates during a scrape so the UI
// can render a live progress bar. A nil reporter is a no-op (keeps the /scrape
// HTTP route and tests simple).
type ProgressReporter func(stage string, percent int)

// Progress stages, emitted in monotonic order during a single scrape.
const (
	StageValidating    = "validating"
	StageRendering     = "rendering"
	StagePageLoaded    = "page_loaded"
	StageExtracting    = "extracting"
	StageBackstop      = "backstop" // paid ZenRows second pass (import miss-path only)
	StageCrossChecking = "cross_checking"
	StageDone          = "done"
)

// stage percentages.
const (
	percentValidating    = 5
	percentRendering     = 20
	percentPageLoaded    = 50
	percentExtracting    = 70
	percentBackstop      = 80
	percentCrossChecking = 90
	percentDone          = 100
)

func (r ProgressReporter) report(stage string, percent int) {
	if r != nil {
		r(stage, percent)
	}
}
