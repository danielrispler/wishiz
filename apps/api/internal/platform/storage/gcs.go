package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"path"
	"strings"

	gcs "cloud.google.com/go/storage"

	"github.com/danielrispler/wishiz/apps/api/internal/platform/randhex"
)

// GCSUploader stores images in a Google Cloud Storage bucket. The bucket uses
// uniform bucket-level access with a public allUsers:objectViewer binding, so
// uploaded objects are world-readable directly from GCS — there is no read
// proxy. Object keys are unguessable 16-byte hex, which is the access control.
type GCSUploader struct {
	client        *gcs.Client
	bucket        string
	publicBaseURL string
}

// NewGCSUploader builds an uploader using Application Default Credentials. On
// Cloud Run that is the service account; locally the SDK honors
// STORAGE_EMULATOR_HOST for a fake-gcs-server. publicBaseURL defaults to the
// canonical https://storage.googleapis.com host when empty.
func NewGCSUploader(ctx context.Context, bucket, publicBaseURL string) (*GCSUploader, error) {
	if strings.TrimSpace(bucket) == "" {
		return nil, fmt.Errorf("storage bucket is required")
	}

	client, err := gcs.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("create gcs client: %w", err)
	}

	base := strings.TrimRight(strings.TrimSpace(publicBaseURL), "/")
	if base == "" {
		base = "https://storage.googleapis.com"
	}

	return &GCSUploader{
		client:        client,
		bucket:        bucket,
		publicBaseURL: base,
	}, nil
}

func (u *GCSUploader) UploadImage(ctx context.Context, params UploadImageParams) (Object, error) {
	if err := ValidateImageContentType(params.ContentType); err != nil {
		return Object{}, err
	}

	key, err := objectKey(params.KeyPrefix, params.FileName)
	if err != nil {
		return Object{}, err
	}

	writer := u.client.Bucket(u.bucket).Object(key).NewWriter(ctx)
	writer.ContentType = params.ContentType
	writer.CacheControl = "public, max-age=31536000, immutable"

	if _, err := io.Copy(writer, params.Body); err != nil {
		_ = writer.Close()
		return Object{}, fmt.Errorf("write object: %w", err)
	}
	if err := writer.Close(); err != nil {
		return Object{}, fmt.Errorf("finalize object: %w", err)
	}

	return Object{
		Key: key,
		URL: publicURL(u.publicBaseURL, u.bucket, key),
	}, nil
}

// publicURL builds the world-readable GCS URL for an object key:
// https://storage.googleapis.com/<bucket>/<key>.
func publicURL(baseURL, bucket, key string) string {
	return strings.TrimRight(baseURL, "/") + "/" + bucket + "/" + key
}

// KeyFromPublicURL reverses publicURL: it extracts the object key from a URL this
// uploader would have produced, or reports ok=false for any URL outside this
// bucket (external/scraped retailer images). It is the single reverse of publicURL
// so the forward/back mapping can never drift — callers needing URL→key cleanup
// (account-deletion image GC) use this rather than re-deriving the prefix.
func (u *GCSUploader) KeyFromPublicURL(url string) (string, bool) {
	prefix := publicURL(u.publicBaseURL, u.bucket, "")
	if !strings.HasPrefix(url, prefix) {
		return "", false
	}
	key := strings.TrimPrefix(url, prefix)
	if key == "" {
		return "", false
	}
	return key, true
}

func objectKey(prefix string, fileName string) (string, error) {
	extension := strings.ToLower(path.Ext(strings.TrimSpace(fileName)))
	if extension == "" {
		extension = ".bin"
	}

	random, err := randhex.String(16)
	if err != nil {
		return "", fmt.Errorf("generate object key: %w", err)
	}

	return path.Join(strings.Trim(prefix, "/"), random+extension), nil
}

// Delete removes the object at key. A missing object is treated as success
// (idempotent) so repeated best-effort cleanup never errors on an already-gone key.
func (u *GCSUploader) Delete(ctx context.Context, key string) error {
	if err := u.client.Bucket(u.bucket).Object(key).Delete(ctx); err != nil {
		if errors.Is(err, gcs.ErrObjectNotExist) {
			return nil
		}
		return fmt.Errorf("delete object %s: %w", key, err)
	}
	return nil
}

// Close releases the underlying GCS client.
func (u *GCSUploader) Close() error {
	return u.client.Close()
}
