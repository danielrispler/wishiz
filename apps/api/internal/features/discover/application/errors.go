package application

import "fmt"

type ErrorCode string

const (
	ErrorCodeValidation   ErrorCode = "validation"
	ErrorCodeNotFound     ErrorCode = "not_found"
	ErrorCodeUnauthorized ErrorCode = "unauthorized"
)

type Error struct {
	Code    ErrorCode
	Message string
	Field   string
}

func (e *Error) Error() string {
	return fmt.Sprintf("[%s] %s", e.Code, e.Message)
}

func AsError(err error) (*Error, bool) {
	if err == nil {
		return nil, false
	}
	var appErr *Error
	if e, ok := err.(*Error); ok {
		appErr = e
		return appErr, true
	}
	return nil, false
}

func ValidationError(field, msg string) error {
	return &Error{Code: ErrorCodeValidation, Message: msg, Field: field}
}

func NotFound(msg string) error {
	return &Error{Code: ErrorCodeNotFound, Message: msg}
}

func Unauthorized(msg string) error {
	return &Error{Code: ErrorCodeUnauthorized, Message: msg}
}
