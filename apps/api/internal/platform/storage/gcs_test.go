package storage

import "testing"

func TestPublicURL(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		base   string
		bucket string
		key    string
		want   string
	}{
		{
			name:   "canonical host",
			base:   "https://storage.googleapis.com",
			bucket: "wishiz-images",
			key:    "wishlists/abc123.png",
			want:   "https://storage.googleapis.com/wishiz-images/wishlists/abc123.png",
		},
		{
			name:   "trailing slash on base is trimmed",
			base:   "https://cdn.example.com/",
			bucket: "bkt",
			key:    "k.jpg",
			want:   "https://cdn.example.com/bkt/k.jpg",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := publicURL(tc.base, tc.bucket, tc.key); got != tc.want {
				t.Fatalf("publicURL(%q,%q,%q) = %q, want %q", tc.base, tc.bucket, tc.key, got, tc.want)
			}
		})
	}
}
