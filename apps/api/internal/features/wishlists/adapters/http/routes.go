package wishlisthttp

import (
	"log/slog"
	"net/http"

	"github.com/danielrispler/wishiz/apps/api/internal/features/wishlists/ports"
)

func RegisterRoutes(mux *http.ServeMux, logger *slog.Logger, repository ports.Repository) {
	_, _, _ = mux, logger, repository
	// Wishlist routes will be added here when the first backend slice is implemented.
}
