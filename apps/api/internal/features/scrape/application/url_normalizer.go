package application

import (
	"context"
	"net/url"
	"strings"
)

var googleDestinationParams = []string{"q", "url", "u", "adurl"}

func NormalizeProductURL(ctx context.Context, resolver HostResolver, rawURL string) (*url.URL, error) {
	parsedURL, err := ValidateProductURL(ctx, resolver, rawURL)
	if err != nil {
		return nil, err
	}

	current := parsedURL
	for range 3 {
		if !isGoogleHost(current.Hostname()) {
			return current, nil
		}

		destination := googleDestinationURL(current)
		if destination == "" {
			return current, nil
		}

		nextURL, err := ValidateProductURL(ctx, resolver, destination)
		if err != nil {
			return nil, err
		}
		current = nextURL
	}

	return current, nil
}

func isGoogleHost(host string) bool {
	normalized := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(host), "."))
	if normalized == "" {
		return false
	}

	labels := strings.Split(normalized, ".")
	for index, label := range labels {
		if label == "google" && index < len(labels)-1 {
			return true
		}
	}
	return false
}

func googleDestinationURL(source *url.URL) string {
	query := source.Query()
	for _, key := range googleDestinationParams {
		for _, value := range query[key] {
			candidate := strings.TrimSpace(value)
			if candidate == "" {
				continue
			}
			parsed, err := url.Parse(candidate)
			if err == nil && parsed.IsAbs() && parsed.Host != "" && (parsed.Scheme == schemeHTTP || parsed.Scheme == schemeHTTPS) {
				return parsed.String()
			}
		}
	}
	return ""
}
