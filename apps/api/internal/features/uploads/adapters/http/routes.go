package uploadshttp

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/storage"
)

const maxUploadBytes int64 = 10 << 20

type Uploader interface {
	UploadImage(ctx context.Context, params storage.UploadImageParams) (storage.Object, error)
	GetObject(ctx context.Context, key string) (storage.ObjectData, error)
}

type handler struct {
	logger   *slog.Logger
	uploader Uploader
}

type uploadImageResponse struct {
	Key string `json:"key"`
	URL string `json:"url"`
}

type AuthMiddleware func(http.HandlerFunc) http.HandlerFunc

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, uploader Uploader, authMiddleware AuthMiddleware) {
	h := handler{
		logger:   logger,
		uploader: uploader,
	}

	if authMiddleware == nil {
		authMiddleware = func(next http.HandlerFunc) http.HandlerFunc {
			return next
		}
	}

	mux.HandleFunc("POST /uploads/images", authMiddleware(withAuthenticatedUser(h.uploadImage)))
	mux.HandleFunc("GET /storage/{key...}", h.proxyStorageObject)
}

func withAuthenticatedUser(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, ok := authctx.UserFromContext(r.Context()); !ok {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
			return
		}
		h(w, r)
	}
}

func (h handler) uploadImage(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxUploadBytes)
	if err := r.ParseMultipartForm(maxUploadBytes); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", "invalid multipart image upload", "")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "image file is required", "file")
		return
	}
	defer file.Close()

	contentType := strings.TrimSpace(header.Header.Get("Content-Type"))
	if contentType == "" {
		contentType = http.DetectContentType(sniffBytes(file))
		if seeker, ok := file.(io.Seeker); ok {
			_, _ = seeker.Seek(0, io.SeekStart)
		}
	}

	object, err := h.uploader.UploadImage(r.Context(), storage.UploadImageParams{
		KeyPrefix:     "wishlists",
		FileName:      header.Filename,
		ContentType:   contentType,
		ContentLength: header.Size,
		Body:          file,
	})
	if err != nil {
		if errors.Is(err, storage.ErrInvalidContentType) {
			httpx.WriteError(w, http.StatusBadRequest, "validation_error", "unsupported image format", "file")
			return
		}
		h.logger.Error("image upload failed", "path", r.URL.Path, "error", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, uploadImageResponse{
		Key: object.Key,
		URL: object.URL,
	})
}

func (h handler) proxyStorageObject(w http.ResponseWriter, r *http.Request) {
	key := r.PathValue("key")
	if key == "" {
		http.NotFound(w, r)
		return
	}

	obj, err := h.uploader.GetObject(r.Context(), key)
	if err != nil {
		h.logger.Error("storage proxy failed", "key", key, "error", err)
		http.NotFound(w, r)
		return
	}
	defer obj.Body.Close()

	if obj.ContentType != "" {
		w.Header().Set("Content-Type", obj.ContentType)
	}
	if obj.ContentLength > 0 {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", obj.ContentLength))
	}
	if obj.CacheControl != "" {
		w.Header().Set("Cache-Control", obj.CacheControl)
	} else {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	}
	if obj.ETag != "" {
		w.Header().Set("ETag", obj.ETag)
	}
	if !obj.LastModified.IsZero() {
		w.Header().Set("Last-Modified", obj.LastModified.UTC().Format(http.TimeFormat))
	}
	if isNotModified(r, obj) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	if _, err := io.Copy(w, obj.Body); err != nil {
		h.logger.Error("storage proxy stream failed", "key", key, "error", err)
	}
}

func isNotModified(r *http.Request, obj storage.ObjectData) bool {
	if match := strings.TrimSpace(r.Header.Get("If-None-Match")); match != "" && obj.ETag != "" {
		for _, candidate := range strings.Split(match, ",") {
			value := strings.TrimSpace(candidate)
			if value == "*" || value == obj.ETag {
				return true
			}
		}
	}

	if modifiedSince := strings.TrimSpace(r.Header.Get("If-Modified-Since")); modifiedSince != "" && !obj.LastModified.IsZero() {
		t, err := http.ParseTime(modifiedSince)
		if err == nil && !obj.LastModified.After(t) {
			return true
		}
	}

	return false
}

func sniffBytes(file io.Reader) []byte {
	buffer := make([]byte, 512)
	count, _ := file.Read(buffer)
	return buffer[:count]
}
