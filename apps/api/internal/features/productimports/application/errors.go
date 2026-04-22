package application

import "errors"

type ErrorCode string

const (
	ErrorCodeValidation ErrorCode = "validation_error"
	ErrorCodeNotFound   ErrorCode = "product_import_not_found"
	ErrorCodeConflict   ErrorCode = "product_import_conflict"
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

func NotFound() error {
	return &Error{Code: ErrorCodeNotFound, Message: "product import job not found"}
}

func Conflict(field string, message string) error {
	return &Error{Code: ErrorCodeConflict, Message: message, Field: field}
}
