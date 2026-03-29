package application

import "errors"

type ErrorCode string

const (
	ErrorCodeValidation       ErrorCode = "validation_error"
	ErrorCodeWishlistNotFound ErrorCode = "wishlist_not_found"
	ErrorCodeItemNotFound     ErrorCode = "wishlist_item_not_found"
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
	return &Error{
		Code:    ErrorCodeValidation,
		Message: message,
		Field:   field,
	}
}

func WishlistNotFound() error {
	return &Error{
		Code:    ErrorCodeWishlistNotFound,
		Message: "wishlist not found",
	}
}

func ItemNotFound() error {
	return &Error{
		Code:    ErrorCodeItemNotFound,
		Message: "wishlist item not found",
	}
}

func AsError(err error) (*Error, bool) {
	var appErr *Error
	if !errors.As(err, &appErr) {
		return nil, false
	}

	return appErr, true
}
