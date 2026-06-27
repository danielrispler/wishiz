package application

import "testing"

func TestInferProxyCountry(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"shop.de":           "de",
		"www.example.co.uk": "gb", // .uk → gb (ISO), not "uk"
		"store.fr":          "fr",
		"brand.example.com": "us", // generic gTLD: pin US (best single commerce exit)
		"x.net":             "us",
		"x.org":             "us",
		"site.eu":           "", // multi-country: no single correct exit
		"localhost":         "", // no dot
		"":                  "",
		"SHOP.DE":           "de", // case-insensitive
		"shop.de.":          "de", // trailing dot
	}
	for host, want := range cases {
		if got := inferProxyCountry(host); got != want {
			t.Errorf("inferProxyCountry(%q) = %q, want %q", host, got, want)
		}
	}
}

func TestVerdictRankOrdering(t *testing.T) {
	t.Parallel()
	if verdictRank(VerdictAutoComplete) <= verdictRank(VerdictNeedsReview) ||
		verdictRank(VerdictNeedsReview) <= verdictRank(VerdictFailed) {
		t.Fatalf("want auto_complete > needs_review > failed, got %d %d %d",
			verdictRank(VerdictAutoComplete), verdictRank(VerdictNeedsReview), verdictRank(VerdictFailed))
	}
}
