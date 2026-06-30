package application

import "errors"

type ErrorCode string

const (
	ErrorCodeValidation ErrorCode = "validation_error"
	ErrorCodeNotFound   ErrorCode = "notification_not_found"
)

type Error struct {
	Code    ErrorCode
	Message string
	Field   string
}

func (e *Error) Error() string {
	return e.Message
}

func ValidationError(field string, message string) error {
	return &Error{Code: ErrorCodeValidation, Message: message, Field: field}
}

func NotFound() error {
	return &Error{Code: ErrorCodeNotFound, Message: "notification not found"}
}

func AsError(err error) (*Error, bool) {
	var appErr *Error
	if !errors.As(err, &appErr) {
		return nil, false
	}
	return appErr, true
}
