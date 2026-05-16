package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
)

var ErrInvalidContentType = errors.New("invalid content type")

type Object struct {
	Key string
	URL string
}

type ObjectData struct {
	Body          io.ReadCloser
	ContentType   string
	ContentLength int64
}

type Uploader interface {
	UploadImage(ctx context.Context, params UploadImageParams) (Object, error)
	GetObject(ctx context.Context, key string) (ObjectData, error)
}

type UploadImageParams struct {
	KeyPrefix     string
	FileName      string
	ContentType   string
	ContentLength int64
	Body          io.Reader
}

func ValidateImageContentType(contentType string) error {
	switch contentType {
	case "image/jpeg", "image/png", "image/webp", "image/gif":
		return nil
	default:
		return fmt.Errorf("%w: %s", ErrInvalidContentType, contentType)
	}
}
