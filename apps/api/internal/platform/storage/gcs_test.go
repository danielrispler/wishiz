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

func TestKeyFromPublicURL(t *testing.T) {
	t.Parallel()
	// KeyFromPublicURL is a pure string reverse of publicURL, so it needs no GCS
	// client — construct the struct directly.
	u := &GCSUploader{bucket: "wishiz-uploads", publicBaseURL: "https://storage.googleapis.com"}

	cases := []struct {
		name    string
		url     string
		wantKey string
		wantOK  bool
	}{
		{
			name:    "our uploaded object",
			url:     "https://storage.googleapis.com/wishiz-uploads/wishlists/deadbeef.jpg",
			wantKey: "wishlists/deadbeef.jpg",
			wantOK:  true,
		},
		{
			name:   "external retailer image",
			url:    "https://images.nordstrom.com/abc/product.jpg",
			wantOK: false,
		},
		{
			name:   "different bucket",
			url:    "https://storage.googleapis.com/some-other-bucket/wishlists/x.jpg",
			wantOK: false,
		},
		{
			name:   "bucket root with no key",
			url:    "https://storage.googleapis.com/wishiz-uploads/",
			wantOK: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			key, ok := u.KeyFromPublicURL(tc.url)
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tc.wantOK)
			}
			if ok && key != tc.wantKey {
				t.Fatalf("key = %q, want %q", key, tc.wantKey)
			}
		})
	}
}

// TestKeyFromPublicURLRoundTrips guards against forward/back drift: a key run
// through publicURL must come back out of KeyFromPublicURL unchanged.
func TestKeyFromPublicURLRoundTrips(t *testing.T) {
	t.Parallel()
	u := &GCSUploader{bucket: "wishiz-uploads", publicBaseURL: "https://cdn.example.com"}
	const key = "wishlists/abc123.png"

	url := publicURL(u.publicBaseURL, u.bucket, key)
	got, ok := u.KeyFromPublicURL(url)
	if !ok || got != key {
		t.Fatalf("round trip: got %q ok=%v, want %q true", got, ok, key)
	}
}
