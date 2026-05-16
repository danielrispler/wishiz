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

type stubUploader struct {
	uploadImage func(context.Context, storage.UploadImageParams) (storage.Object, error)
}

func (s stubUploader) UploadImage(ctx context.Context, params storage.UploadImageParams) (storage.Object, error) {
	return s.uploadImage(ctx, params)
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
