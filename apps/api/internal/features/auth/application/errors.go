package application

import "errors"

type ErrorCode string

const (
	ErrorCodeValidation   ErrorCode = "validation_error"
	ErrorCodeUnauthorized ErrorCode = "unauthorized"
	ErrorCodeConflict     ErrorCode = "conflict"
	ErrorCodeNotFound     ErrorCode = "not_found"
)

type Error struct {
	Code    ErrorCode
	Message string
	Field   string
}

func (e *Error) Error() string {
	return e.Message
}

func AsError(err error) (*Error, bool) {
	var appErr *Error
	ok := errors.As(err, &appErr)
	return appErr, ok
}

func ValidationError(field string, message string) error {
	return &Error{Code: ErrorCodeValidation, Message: message, Field: field}
}

func Unauthorized(message string) error {
	return &Error{Code: ErrorCodeUnauthorized, Message: message}
}

func Conflict(field string, message string) error {
	return &Error{Code: ErrorCodeConflict, Message: message, Field: field}
}

func NotFound(message string) error {
	return &Error{Code: ErrorCodeNotFound, Message: message}
}
