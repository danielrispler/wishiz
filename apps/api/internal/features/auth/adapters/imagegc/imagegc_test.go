package imagegc

import (
	"context"
	"io"
	"log/slog"
	"strings"
	"testing"
)

func newTestCollector(store bucketStore) *Collector {
	return New(nil, store, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

// fakeStore stands in for *storage.GCSUploader: it records deletions and answers
// KeyFromPublicURL the same way (own bucket -> key, external -> not ok). The
// URL->key mapping itself is exercised against the real uploader in the storage
// package's gcs_test.go (single source of truth) — here we only need a stub.
type fakeStore struct {
	prefix  string
	deleted []string
}

func (f *fakeStore) KeyFromPublicURL(url string) (string, bool) {
	if !strings.HasPrefix(url, f.prefix) {
		return "", false
	}
	key := strings.TrimPrefix(url, f.prefix)
	if key == "" {
		return "", false
	}
	return key, true
}

func (f *fakeStore) Delete(_ context.Context, key string) error {
	f.deleted = append(f.deleted, key)
	return nil
}

func TestDeleteObjectsDeletesEachKey(t *testing.T) {
	t.Parallel()
	store := &fakeStore{prefix: "https://storage.googleapis.com/wishiz-uploads/"}
	c := newTestCollector(store)

	c.DeleteObjects(context.Background(), []string{"wishlists/a.jpg", "wishlists/b.jpg"})

	if len(store.deleted) != 2 || store.deleted[0] != "wishlists/a.jpg" || store.deleted[1] != "wishlists/b.jpg" {
		t.Fatalf("unexpected deletions: %v", store.deleted)
	}
}
