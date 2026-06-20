//go:build eval

package eval

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

// Expectation is the sidecar `<name>.json` for each `<name>.html` fixture.
type Expectation struct {
	URL      string `json:"url"`
	Name     string `json:"name"`
	Amount   string `json:"amount"`
	Currency string `json:"currency"`
	Image    string `json:"image"`
	Verdict  string `json:"verdict"`
}

type evalCase struct {
	Name   string
	HTML   string
	Expect Expectation
}

func loadCases(t *testing.T) []evalCase {
	t.Helper()
	htmls, err := filepath.Glob("testdata/*.html")
	if err != nil {
		t.Fatalf("glob testdata: %v", err)
	}
	if len(htmls) == 0 {
		t.Fatal("no fixtures in testdata/ — add <name>.html + <name>.json")
	}

	var cases []evalCase
	for _, htmlPath := range htmls {
		base := strings.TrimSuffix(htmlPath, ".html")
		html, err := os.ReadFile(htmlPath)
		if err != nil {
			t.Fatalf("read %s: %v", htmlPath, err)
		}
		expectRaw, err := os.ReadFile(base + ".json")
		if err != nil {
			t.Fatalf("read expectation for %s: %v", htmlPath, err)
		}
		var expect Expectation
		if err := json.Unmarshal(expectRaw, &expect); err != nil {
			t.Fatalf("parse expectation %s.json: %v", base, err)
		}
		cases = append(cases, evalCase{Name: filepath.Base(base), HTML: string(html), Expect: expect})
	}
	return cases
}

type fieldScore struct{ tp, fp, fn int }

func (s *fieldScore) observe(predicted, expected string) {
	predicted, expected = strings.TrimSpace(predicted), strings.TrimSpace(expected)
	switch {
	case expected != "" && predicted == expected:
		s.tp++
	case expected != "" && predicted != expected:
		s.fn++
		if predicted != "" {
			s.fp++
		}
	case expected == "" && predicted != "":
		s.fp++
	}
}

func (s fieldScore) precision() float64 {
	if s.tp+s.fp == 0 {
		return 1
	}
	return float64(s.tp) / float64(s.tp+s.fp)
}

func (s fieldScore) recall() float64 {
	if s.tp+s.fn == 0 {
		return 1
	}
	return float64(s.tp) / float64(s.tp+s.fn)
}

func TestScoringHarness(t *testing.T) {
	cases := loadCases(t)
	engine := application.NewEngine(application.EngineConfig{})

	var (
		total              = len(cases)
		autoCompletes      int
		falseAutoCompletes int
		name, amount       fieldScore
		currency, image    fieldScore
	)

	for _, c := range cases {
		product := engine.Reconcile(engine.Extract(c.HTML, c.Expect.URL, nil), c.Expect.URL)

		name.observe(product.Name, c.Expect.Name)
		amount.observe(product.PriceAmount, c.Expect.Amount)
		currency.observe(product.PriceCurrency, c.Expect.Currency)
		image.observe(product.ImageURL, c.Expect.Image)

		if string(product.Verdict) != c.Expect.Verdict {
			t.Errorf("%s: verdict = %q, want %q (reasons %v)", c.Name, product.Verdict, c.Expect.Verdict, product.Reasons)
		}

		if product.Verdict == application.VerdictAutoComplete {
			autoCompletes++
			if !allFieldsCorrect(product, c.Expect) {
				falseAutoCompletes++
				t.Errorf("FALSE AUTO-COMPLETE %s: got name=%q amount=%q %s image=%q",
					c.Name, product.Name, product.PriceAmount, product.PriceCurrency, product.ImageURL)
			}
		}
	}

	autoRate := float64(autoCompletes) / float64(total)
	falseRate := float64(falseAutoCompletes) / float64(total)

	t.Logf("cases=%d auto_complete=%.1f%% false_auto_complete=%.2f%%", total, autoRate*100, falseRate*100)
	t.Logf("precision/recall  name=%.2f/%.2f amount=%.2f/%.2f currency=%.2f/%.2f image=%.2f/%.2f",
		name.precision(), name.recall(), amount.precision(), amount.recall(),
		currency.precision(), currency.recall(), image.precision(), image.recall())

	if falseRate >= 0.01 {
		t.Fatalf("false-auto-complete rate %.2f%% exceeds 1%% ceiling", falseRate*100)
	}
}

func allFieldsCorrect(product application.Product, expect Expectation) bool {
	return product.Name == expect.Name &&
		product.PriceAmount == expect.Amount &&
		product.PriceCurrency == expect.Currency &&
		product.ImageURL == expect.Image
}
