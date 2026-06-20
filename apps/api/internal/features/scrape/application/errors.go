package application

import "errors"

type ErrorCode string

const (
	ErrorCodeBadRequest ErrorCode = "bad_request"
	ErrorCodeScrape     ErrorCode = "scrape_failed"
	ErrorCodeTimeout    ErrorCode = "scrape_timeout"
	// ErrorCodeUnsupported marks a site that hard-blocks automated access
	// (anti-bot interstitial). Distinct from a transient scrape failure: the
	// caller should NOT auto-retry — the page is unreachable to the scraper.
	ErrorCodeUnsupported ErrorCode = "site_unsupported"
)

type Error struct {
	Code    ErrorCode
	Message string
}

func (e *Error) Error() string {
	return e.Message
}

func BadRequest(message string) error {
	return &Error{
		Code:    ErrorCodeBadRequest,
		Message: message,
	}
}

func ScrapeFailed(message string) error {
	return &Error{
		Code:    ErrorCodeScrape,
		Message: message,
	}
}

func Timeout(message string) error {
	return &Error{
		Code:    ErrorCodeTimeout,
		Message: message,
	}
}

func Unsupported(message string) error {
	return &Error{
		Code:    ErrorCodeUnsupported,
		Message: message,
	}
}

func AsError(err error) (*Error, bool) {
	var appErr *Error
	if errors.As(err, &appErr) {
		return appErr, true
	}

	return nil, false
}
