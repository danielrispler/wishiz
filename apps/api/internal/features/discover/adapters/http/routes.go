package discoverhttp

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/application"
	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/domain"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/authctx"
	httpx "github.com/danielrispler/wishiz/apps/api/internal/platform/http"
)

type AuthMiddleware func(http.HandlerFunc) http.HandlerFunc

type Service interface {
	GetFeed(ctx context.Context, userID string, brands []string) (application.DiscoverFeed, error)
	ToggleSave(ctx context.Context, userID, productID string) (bool, int, error)
	GrabStarterPack(ctx context.Context, userID, packID, wishlistID string) (int, error)
	SeedProduct(ctx context.Context, rawURL, category string) (domain.DiscoverProduct, error)
	CreateStarterPack(ctx context.Context, title, subtitle, coverImageURL string, productIDs []string) (domain.StarterPack, error)
}

type handler struct {
	logger      *slog.Logger
	service     Service
	authService authGetter
	internalKey string
}

type authGetter interface {
	GetPreferences(ctx context.Context, userID string) ([]string, error)
}

func RegisterRoutes(
	mux *http.ServeMux,
	logger *slog.Logger,
	service Service,
	authPrefs authGetter,
	authMiddleware AuthMiddleware,
	internalKey string,
) {
	h := handler{
		logger:      logger,
		service:     service,
		authService: authPrefs,
		internalKey: internalKey,
	}

	mux.HandleFunc("GET /discover/feed", authMiddleware(h.getFeed))
	mux.HandleFunc("POST /discover/products/{id}/save", authMiddleware(h.toggleSave))
	mux.HandleFunc("POST /discover/starter-packs/{id}/grab", authMiddleware(h.grabStarterPack))

	mux.HandleFunc("POST /internal/discover/products", h.requireInternalKey(h.seedProduct))
	mux.HandleFunc("POST /internal/discover/starter-packs", h.requireInternalKey(h.createStarterPack))
}

func (h handler) requireInternalKey(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if h.internalKey == "" || r.Header.Get("X-Internal-Key") != h.internalKey {
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "invalid internal key", "")
			return
		}
		next(w, r)
	}
}

// ---- Feed ----

type feedResponse struct {
	StarterPacks []starterPackResponse `json:"starterPacks"`
	Trending     []productResponse     `json:"trending"`
	ForYou       []productResponse     `json:"forYou"`
}

func (h handler) getFeed(w http.ResponseWriter, r *http.Request) {
	user, ok := authctx.UserFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
		return
	}

	brands, err := h.authService.GetPreferences(r.Context(), user.ID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	feed, err := h.service.GetFeed(r.Context(), user.ID, brands)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, feedResponse{
		StarterPacks: mapStarterPacks(feed.StarterPacks),
		Trending:     mapProducts(feed.Trending),
		ForYou:       mapProducts(feed.ForYou),
	})
}

// ---- Toggle save ----

type toggleSaveResponse struct {
	Saved     bool `json:"saved"`
	SaveCount int  `json:"saveCount"`
}

func (h handler) toggleSave(w http.ResponseWriter, r *http.Request) {
	user, ok := authctx.UserFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
		return
	}

	productID := r.PathValue("id")
	saved, count, err := h.service.ToggleSave(r.Context(), user.ID, productID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, toggleSaveResponse{Saved: saved, SaveCount: count})
}

// ---- Grab starter pack ----

type grabStarterPackRequest struct {
	WishlistID string `json:"wishlistId"`
}

type grabStarterPackResponse struct {
	ItemsAdded int `json:"itemsAdded"`
}

func (h handler) grabStarterPack(w http.ResponseWriter, r *http.Request) {
	user, ok := authctx.UserFromContext(r.Context())
	if !ok {
		httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "authorization is required", "")
		return
	}

	packID := r.PathValue("id")

	var req grabStarterPackRequest
	if err := httpx.DecodeJSON(w, r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	n, err := h.service.GrabStarterPack(r.Context(), user.ID, packID, req.WishlistID)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusOK, grabStarterPackResponse{ItemsAdded: n})
}

// ---- Internal: seed product ----

type seedProductRequest struct {
	URL      string `json:"url"`
	Category string `json:"category"`
}

func (h handler) seedProduct(w http.ResponseWriter, r *http.Request) {
	var req seedProductRequest
	if err := httpx.DecodeJSON(w, r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	product, err := h.service.SeedProduct(r.Context(), req.URL, req.Category)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, mapProduct(product))
}

// ---- Internal: create starter pack ----

type createStarterPackRequest struct {
	Title         string   `json:"title"`
	Subtitle      string   `json:"subtitle"`
	CoverImageURL string   `json:"coverImageUrl"`
	ProductIDs    []string `json:"productIds"`
}

func (h handler) createStarterPack(w http.ResponseWriter, r *http.Request) {
	var req createStarterPackRequest
	if err := httpx.DecodeJSON(w, r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_request", err.Error(), "")
		return
	}

	pack, err := h.service.CreateStarterPack(r.Context(), req.Title, req.Subtitle, req.CoverImageURL, req.ProductIDs)
	if err != nil {
		h.writeError(w, r, err)
		return
	}

	httpx.WriteJSON(w, http.StatusCreated, mapStarterPack(pack))
}

// ---- Error handling ----

func (h handler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	appErr, ok := application.AsError(err)
	if !ok {
		h.logger.Error("discover request failed", "method", r.Method, "path", r.URL.Path, "error", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
		return
	}
	switch appErr.Code {
	case application.ErrorCodeValidation:
		httpx.WriteError(w, http.StatusBadRequest, string(appErr.Code), appErr.Message, appErr.Field)
	case application.ErrorCodeNotFound:
		httpx.WriteError(w, http.StatusNotFound, string(appErr.Code), appErr.Message, appErr.Field)
	case application.ErrorCodeUnauthorized:
		httpx.WriteError(w, http.StatusUnauthorized, string(appErr.Code), appErr.Message, appErr.Field)
	default:
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "internal server error", "")
	}
}

// ---- Response mappers ----

type productResponse struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Brand       string  `json:"brand"`
	Category    string  `json:"category"`
	ImageURL    string  `json:"imageUrl"`
	ProductURL  *string `json:"productUrl"`
	SaveCount   int     `json:"saveCount"`
	SavedByUser bool    `json:"savedByUser"`
	PriceLabel  *string `json:"priceLabel"`
	Gender      *string `json:"gender"`
	ProductType *string `json:"productType"`
}

type starterPackResponse struct {
	ID            string            `json:"id"`
	Title         string            `json:"title"`
	Subtitle      string            `json:"subtitle"`
	CoverImageURL string            `json:"coverImageUrl"`
	ItemCount     int               `json:"itemCount"`
	PreviewItems  []string          `json:"previewItems"`
	Items         []productResponse `json:"items"`
}

func mapProduct(p domain.DiscoverProduct) productResponse {
	return productResponse{
		ID:          p.ID,
		Title:       p.Title,
		Brand:       p.Brand,
		Category:    p.Category,
		ImageURL:    p.ImageURL,
		ProductURL:  p.ProductURL,
		SaveCount:   p.SaveCount,
		SavedByUser: p.SavedByUser,
		PriceLabel:  p.PriceLabel,
		Gender:      p.Gender,
		ProductType: p.ProductType,
	}
}

func mapProducts(products []domain.DiscoverProduct) []productResponse {
	out := make([]productResponse, len(products))
	for i, p := range products {
		out[i] = mapProduct(p)
	}
	return out
}

func mapStarterPack(p domain.StarterPack) starterPackResponse {
	previews := p.PreviewItems
	if previews == nil {
		previews = []string{}
	}
	return starterPackResponse{
		ID:            p.ID,
		Title:         p.Title,
		Subtitle:      p.Subtitle,
		CoverImageURL: p.CoverImageURL,
		ItemCount:     p.ItemCount,
		PreviewItems:  previews,
		Items:         mapProducts(p.Items),
	}
}

func mapStarterPacks(packs []domain.StarterPack) []starterPackResponse {
	out := make([]starterPackResponse, len(packs))
	for i, p := range packs {
		out[i] = mapStarterPack(p)
	}
	return out
}
