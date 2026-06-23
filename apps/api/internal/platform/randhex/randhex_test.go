package randhex

import (
	"regexp"
	"testing"
)

var hexOnly = regexp.MustCompile("^[0-9a-f]*$")

func TestStringLengthAndCharset(t *testing.T) {
	t.Parallel()

	for _, n := range []int{0, 1, 16, 32} {
		s, err := String(n)
		if err != nil {
			t.Fatalf("String(%d): %v", n, err)
		}
		if len(s) != 2*n {
			t.Fatalf("String(%d): want %d hex chars, got %d", n, 2*n, len(s))
		}
		if !hexOnly.MatchString(s) {
			t.Fatalf("String(%d): non-hex output %q", n, s)
		}
	}
}

func TestStringIsRandom(t *testing.T) {
	t.Parallel()

	a, _ := String(16)
	b, _ := String(16)
	if a == b {
		t.Fatalf("two String(16) calls returned identical output %q", a)
	}
}
