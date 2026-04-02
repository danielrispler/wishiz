package healthhttp

import (
	"net/http"

	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

func RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		httpx.WriteJSON(w, http.StatusOK, map[string]string{
			"status": "ok",
		})
	})
}
