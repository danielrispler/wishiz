package httpx

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

type ErrorResponse struct {
	Error ErrorBody `json:"error"`
}

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Field   string `json:"field,omitempty"`
}

func WriteJSON(w http.ResponseWriter, statusCode int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	if err := json.NewEncoder(w).Encode(payload); err != nil {
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
	}
}

func WriteError(w http.ResponseWriter, statusCode int, code string, message string, field string) {
	WriteJSON(w, statusCode, ErrorResponse{
		Error: ErrorBody{
			Code:    code,
			Message: message,
			Field:   field,
		},
	})
}

func DecodeJSON(r *http.Request, dst any) error {
	defer r.Body.Close()

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()

	if err := decoder.Decode(dst); err != nil {
		if errors.Is(err, io.EOF) {
			return fmt.Errorf("request body is required")
		}

		return err
	}

	var extra json.RawMessage
	if err := decoder.Decode(&extra); err != nil {
		if errors.Is(err, io.EOF) {
			return nil
		}

		return fmt.Errorf("request body must contain a single JSON object")
	}

	return fmt.Errorf("request body must contain a single JSON object")
}
