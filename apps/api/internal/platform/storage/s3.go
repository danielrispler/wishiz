package storage

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"path"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type S3Config struct {
	Endpoint        string
	Region          string
	Bucket          string
	AccessKeyID     string
	SecretAccessKey string
	UsePathStyle    bool
	PublicBaseURL   string
}

type S3Uploader struct {
	bucket        string
	publicBaseURL string
	client        *s3.Client
}

func NewS3Uploader(cfg S3Config) (*S3Uploader, error) {
	if strings.TrimSpace(cfg.Endpoint) == "" {
		return nil, fmt.Errorf("storage endpoint is required")
	}
	if strings.TrimSpace(cfg.Bucket) == "" {
		return nil, fmt.Errorf("storage bucket is required")
	}
	if strings.TrimSpace(cfg.AccessKeyID) == "" {
		return nil, fmt.Errorf("storage access key is required")
	}
	if strings.TrimSpace(cfg.SecretAccessKey) == "" {
		return nil, fmt.Errorf("storage secret key is required")
	}

	awsConfig := aws.Config{
		Region:      cfg.Region,
		Credentials: credentials.NewStaticCredentialsProvider(cfg.AccessKeyID, cfg.SecretAccessKey, ""),
	}

	client := s3.NewFromConfig(awsConfig, func(options *s3.Options) {
		options.BaseEndpoint = aws.String(cfg.Endpoint)
		options.UsePathStyle = cfg.UsePathStyle
	})

	publicBaseURL := strings.TrimRight(strings.TrimSpace(cfg.PublicBaseURL), "/")
	if publicBaseURL == "" {
		publicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.Endpoint), "/")
	}

	return &S3Uploader{
		bucket:        cfg.Bucket,
		publicBaseURL: publicBaseURL,
		client:        client,
	}, nil
}

func (u *S3Uploader) UploadImage(ctx context.Context, params UploadImageParams) (Object, error) {
	if err := ValidateImageContentType(params.ContentType); err != nil {
		return Object{}, err
	}

	key, err := objectKey(params.KeyPrefix, params.FileName)
	if err != nil {
		return Object{}, err
	}

	_, err = u.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(u.bucket),
		Key:           aws.String(key),
		Body:          params.Body,
		ContentLength: aws.Int64(params.ContentLength),
		ContentType:   aws.String(params.ContentType),
		CacheControl:  aws.String("public, max-age=31536000, immutable"),
	})
	if err != nil {
		return Object{}, fmt.Errorf("put object: %w", err)
	}

	return Object{
		Key: key,
		URL: u.publicURL(key),
	}, nil
}

func (u *S3Uploader) publicURL(key string) string {
	baseURL, err := url.Parse(u.publicBaseURL)
	if err != nil || baseURL.Scheme == "" || baseURL.Host == "" {
		return fmt.Sprintf("%s/%s/%s", strings.TrimRight(u.publicBaseURL, "/"), u.bucket, key)
	}

	baseURL.Path = path.Join(baseURL.Path, u.bucket, key)
	return baseURL.String()
}

func objectKey(prefix string, fileName string) (string, error) {
	extension := strings.ToLower(path.Ext(strings.TrimSpace(fileName)))
	if extension == "" {
		extension = ".bin"
	}

	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return "", fmt.Errorf("generate object key: %w", err)
	}

	return path.Join(strings.Trim(prefix, "/"), hex.EncodeToString(random)+extension), nil
}
