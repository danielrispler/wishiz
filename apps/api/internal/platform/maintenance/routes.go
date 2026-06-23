package maintenance

import (
	"context"
	"net/http"

	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

// Sweeper runs one maintenance pass, returning a non-nil error when a step
// genuinely failed (shutdown/ctx-cancel excluded). *Worker satisfies it.
type Sweeper interface {
	Sweep(ctx context.Context) error
}

// RegisterRoutes mounts POST /internal/maintenance on the api role. The sweep is
// light (DB-only) so it runs synchronously in the request. Access is gated at the
// platform layer (Cloud Run IAM / OIDC from Cloud Scheduler); there is no
// app-level auth here. A sweep failure returns 500 so Cloud Scheduler records the
// failure instead of a misleading success.
func RegisterRoutes(mux *http.ServeMux, sweeper Sweeper) {
	mux.HandleFunc("POST /internal/maintenance", func(w http.ResponseWriter, r *http.Request) {
		if err := sweeper.Sweep(r.Context()); err != nil {
			httpx.WriteError(w, http.StatusInternalServerError, "maintenance_sweep_failed", err.Error(), "")
			return
		}
		httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
}
