package application

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/danielrispler/wishiz/apps/api/internal/features/notifications/domain"
)

// TestNotificationTypeCheckMatchesDomainTypes guards against drift between the Go
// domain.AllTypes() set written to notifications.type and the SQL CHECK that
// validates it. Reading the migration SQL (rather than mirroring the list in Go)
// makes drift impossible to merge: add a Type without widening the CHECK and this
// fails. Mirrors extractors/sourcenames_test.go for price_source.
func TestNotificationTypeCheckMatchesDomainTypes(t *testing.T) {
	t.Parallel()

	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	dir := filepath.Dir(thisFile)
	migration := filepath.Join(
		dir, "..", "..", "..", "platform", "db", "migrations", "000003_notifications.up.sql",
	)
	raw, err := os.ReadFile(migration)
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}

	got := map[string]bool{}
	for _, v := range parseNotificationTypeCheck(t, string(raw)) {
		got[v] = true
	}
	want := map[string]bool{}
	for _, ty := range domain.AllTypes() {
		want[ty] = true
	}

	for v := range want {
		if !got[v] {
			t.Errorf("domain Type %q written to notifications.type but missing from the CHECK constraint", v)
		}
	}
	for v := range got {
		if !want[v] {
			t.Errorf("CHECK constraint allows %q but no domain Type produces it (dead value)", v)
		}
	}
}

func parseNotificationTypeCheck(t *testing.T, sql string) []string {
	t.Helper()
	re := regexp.MustCompile(`notifications_type_check\s+CHECK\s*\([^)]*type\s+IN\s*\(([^)]*)\)`)
	m := re.FindStringSubmatch(sql)
	if m == nil {
		t.Fatal("could not find notifications_type_check IN (...) list in migration")
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
