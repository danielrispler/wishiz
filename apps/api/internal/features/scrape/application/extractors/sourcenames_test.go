package extractors

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"
)

// TestPriceSourceCheckMatchesSourceNames guards against drift between the Go
// SourceName set written to product_import_jobs.price_source and the SQL CHECK
// constraint that validates it. Reading the migration SQL (rather than
// mirroring the list in Go) makes drift impossible to merge, not merely
// detectable: add a SourceName without widening the CHECK and this fails.
func TestPriceSourceCheckMatchesSourceNames(t *testing.T) {
	t.Parallel()

	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	dir := filepath.Dir(thisFile)
	migration := filepath.Join(
		dir, "..", "..", "..", "..", "platform", "db", "migrations", "000001_init_wishlists.up.sql",
	)
	raw, err := os.ReadFile(migration)
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}

	got := map[string]bool{}
	for _, v := range parsePriceSourceCheck(t, string(raw)) {
		got[v] = true
	}
	want := map[string]bool{}
	for _, s := range AllSourceNames() {
		want[string(s)] = true
	}

	for v := range want {
		if !got[v] {
			t.Errorf("SourceName %q written to price_source but missing from the CHECK constraint", v)
		}
	}
	for v := range got {
		if !want[v] {
			t.Errorf("CHECK constraint allows %q but no SourceName produces it (dead value)", v)
		}
	}
}

func parsePriceSourceCheck(t *testing.T, sql string) []string {
	t.Helper()
	re := regexp.MustCompile(`price_source_check\s+CHECK\s*\([^)]*price_source\s+IN\s*\(([^)]*)\)`)
	m := re.FindStringSubmatch(sql)
	if m == nil {
		t.Fatal("could not find price_source CHECK IN (...) list in migration")
	}
	var out []string
	for _, tok := range strings.Split(m[1], ",") {
		tok = strings.Trim(strings.TrimSpace(tok), "'")
		if tok != "" {
			out = append(out, tok)
		}
	}
	sort.Strings(out)
	return out
}
