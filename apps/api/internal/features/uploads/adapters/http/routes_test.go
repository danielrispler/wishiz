package uploadshttp

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"testing"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/storage"
)

func TestUploadImageReturnsCreatedObject(t *testing.T) {
	t.Parallel()

	uploader := stubUploader{
		uploadImage: func(_ context.Context, params storage.UploadImageParams) (storage.Object, error) {
			if params.FileName != "cover.png" {
				t.Fatalf("expected uploaded file name, got %q", params.FileName)
			}
			if params.ContentType != "image/png" {
				t.Fatalf("expected content type image/png, got %q", params.ContentType)
			}
			data, err := io.ReadAll(params.Body)
			if err != nil {
				t.Fatalf("read upload body: %v", err)
			}
			if string(data) != "png-data" {
				t.Fatalf("expected body to be passed through, got %q", string(data))
			}

			return storage.Object{
				Key: "wishlists/object.png",
				URL: "http://127.0.0.1:9000/wishiz-images/wishlists/object.png",
			}, nil
		},
	}

	response := performUploadRequest(t, uploader, "cover.png", "image/png", []byte("png-data"))
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d with body %s", response.Code, response.Body.String())
	}

	var payload uploadImageResponse
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Key == "" || payload.URL == "" {
		t.Fatalf("expected key and url in response, got %#v", payload)
	}
}

func TestUploadImageRejectsUnsupportedContentType(t *testing.T) {
	t.Parallel()

	uploader := stubUploader{
		uploadImage: func(_ context.Context, params storage.UploadImageParams) (storage.Object, error) {
			return storage.Object{}, storage.ValidateImageContentType(params.ContentType)
		},
	}

	response := performUploadRequest(t, uploader, "notes.txt", "text/plain", []byte("hello"))
	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d with body %s", response.Code, response.Body.String())
	}
}

func TestProxyStorageObjectForwardsCacheHeaders(t *testing.T) {
	t.Parallel()

	lastModified := time.Date(2026, time.May, 16, 12, 30, 0, 0, time.UTC)
	uploader := stubUploader{
		getObject: func(_ context.Context, key string) (storage.ObjectData, error) {
			if key != "wishlists/object.png" {
				t.Fatalf("expected key to be passed through, got %q", key)
			}
			return storage.ObjectData{
				Body:          io.NopCloser(bytes.NewReader([]byte("image-bytes"))),
				ContentType:   "image/png",
				ContentLength: int64(len("image-bytes")),
				CacheControl:  "public, max-age=31536000, immutable",
				ETag:          "\"abc123\"",
				LastModified:  lastModified,
			}, nil
		},
	}

	recorder := performStorageRequest(t, uploader, nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", recorder.Code)
	}
	if got := recorder.Header().Get("Content-Type"); got != "image/png" {
		t.Fatalf("expected content type to be forwarded, got %q", got)
	}
	if got := recorder.Header().Get("Cache-Control"); got != "public, max-age=31536000, immutable" {
		t.Fatalf("expected cache-control to be forwarded, got %q", got)
	}
	if got := recorder.Header().Get("ETag"); got != "\"abc123\"" {
		t.Fatalf("expected etag to be forwarded, got %q", got)
	}
	if got := recorder.Header().Get("Last-Modified"); got != lastModified.Format(http.TimeFormat) {
		t.Fatalf("expected last-modified to be forwarded, got %q", got)
	}
	if got := recorder.Body.String(); got != "image-bytes" {
		t.Fatalf("expected proxy to stream response body, got %q", got)
	}
}

func TestProxyStorageObjectReturnsNotModifiedWhenETagMatches(t *testing.T) {
	t.Parallel()

	uploader := stubUploader{
		getObject: func(_ context.Context, _ string) (storage.ObjectData, error) {
			return storage.ObjectData{
				Body:         io.NopCloser(bytes.NewReader([]byte("image-bytes"))),
				ETag:         "\"abc123\"",
				LastModified: time.Date(2026, time.May, 16, 12, 30, 0, 0, time.UTC),
			}, nil
		},
	}

	headers := make(http.Header)
	headers.Set("If-None-Match", "\"abc123\"")
	recorder := performStorageRequest(t, uploader, headers)
	if recorder.Code != http.StatusNotModified {
		t.Fatalf("expected 304, got %d", recorder.Code)
	}
	if recorder.Body.Len() != 0 {
		t.Fatalf("expected empty body for 304, got %q", recorder.Body.String())
	}
}

type stubUploader struct {
	uploadImage func(context.Context, storage.UploadImageParams) (storage.Object, error)
	getObject   func(context.Context, string) (storage.ObjectData, error)
}

func (s stubUploader) UploadImage(ctx context.Context, params storage.UploadImageParams) (storage.Object, error) {
	return s.uploadImage(ctx, params)
}

func (s stubUploader) GetObject(ctx context.Context, key string) (storage.ObjectData, error) {
	if s.getObject == nil {
		return storage.ObjectData{}, nil
	}
	return s.getObject(ctx, key)
}

func performUploadRequest(
	t *testing.T,
	uploader Uploader,
	fileName string,
	contentType string,
	body []byte,
) *httptest.ResponseRecorder {
	t.Helper()

	mux := http.NewServeMux()
	RegisterRoutes(
		mux,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		uploader,
		func(next http.HandlerFunc) http.HandlerFunc {
			return func(w http.ResponseWriter, r *http.Request) {
				next(
					w,
					r.WithContext(authctx.WithUser(r.Context(), authctx.User{
						ID:    "11111111-1111-1111-1111-111111111111",
						Email: "maya@example.com",
					})),
				)
			}
		},
	)

	requestBody := &bytes.Buffer{}
	writer := multipart.NewWriter(requestBody)
	header := textproto.MIMEHeader{}
	header.Set("Content-Disposition", `form-data; name="file"; filename="`+fileName+`"`)
	if contentType != "" {
		header.Set("Content-Type", contentType)
	}
	fileWriter, err := writer.CreatePart(header)
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := fileWriter.Write(body); err != nil {
		t.Fatalf("write form file: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	request := httptest.NewRequest(http.MethodPost, "/uploads/images", requestBody)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	if contentType != "" {
		request.Header.Set("X-Test-Content-Type", contentType)
	}

	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	return recorder
}

func performStorageRequest(
	t *testing.T,
	uploader Uploader,
	headers http.Header,
) *httptest.ResponseRecorder {
	t.Helper()

	mux := http.NewServeMux()
	RegisterRoutes(
		mux,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
		uploader,
		nil,
	)

	request := httptest.NewRequest(http.MethodGet, "/storage/wishlists/object.png", http.NoBody)
	for key, values := range headers {
		for _, value := range values {
			request.Header.Add(key, value)
		}
	}

	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	return recorder
}
