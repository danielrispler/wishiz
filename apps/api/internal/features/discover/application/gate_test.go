package application

import (
	"testing"

	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

func TestIsSeedableOnlyAcceptsConfidentProducts(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		in   scrapeapp.Product
		want bool
	}{
		{
			name: "auto_complete with name and image is seedable",
			in:   scrapeapp.Product{Name: "Wool Coat", ImageURL: "https://x/i.jpg", Verdict: scrapeapp.VerdictAutoComplete},
			want: true,
		},
		{
			name: "needs_review is rejected",
			in:   scrapeapp.Product{Name: "Wool Coat", ImageURL: "https://x/i.jpg", Verdict: scrapeapp.VerdictNeedsReview},
			want: false,
		},
		{
			name: "failed is rejected",
			in:   scrapeapp.Product{Name: "Wool Coat", ImageURL: "https://x/i.jpg", Verdict: scrapeapp.VerdictFailed},
			want: false,
		},
		{
			name: "empty verdict is rejected",
			in:   scrapeapp.Product{Name: "Wool Coat", ImageURL: "https://x/i.jpg"},
			want: false,
		},
		{
			name: "auto_complete but missing name is rejected",
			in:   scrapeapp.Product{Name: "  ", ImageURL: "https://x/i.jpg", Verdict: scrapeapp.VerdictAutoComplete},
			want: false,
		},
		{
			name: "auto_complete but missing image is rejected",
			in:   scrapeapp.Product{Name: "Wool Coat", ImageURL: "", Verdict: scrapeapp.VerdictAutoComplete},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := isSeedable(tt.in); got != tt.want {
				t.Fatalf("isSeedable(%+v) = %v, want %v", tt.in, got, tt.want)
			}
		})
	}
}
