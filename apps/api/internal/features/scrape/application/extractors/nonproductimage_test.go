package extractors

import "testing"

// Regression (luluandgeorgia.com): a redirect to /cart served og:image
// `social-image.jpg` — the Shopify store-default share asset (a dead 404) — which
// won the image consensus over the correct Shopify-probe product image. The
// generic store/share/placeholder basenames must be rejected as non-product
// images so the real product image wins.
func TestIsNonProductImageURL_GenericBasenames(t *testing.T) {
	t.Parallel()
	reject := []string{
		"https://www.luluandgeorgia.com/cdn/shop/files/social-image.jpg?v=446137",
		"https://cdn.example.com/social-image_1024x.jpg",
		"https://cdn.example.com/files/social_image.png",
		"https://cdn.example.com/placeholder.png",
		"https://cdn.example.com/no-image.jpg",
		"https://cdn.example.com/default-product.jpg",
		"https://cdn.example.com/assets/logo.svg",
		"https://cdn.example.com/favicon.ico",
	}
	for _, u := range reject {
		if !IsNonProductImageURL(u) {
			t.Errorf("expected REJECT (non-product), got accept: %s", u)
		}
	}

	keep := []string{
		"https://cdn.shopify.com/s/files/CloverStool_RustVelvet_3623_1024x.jpg?v=1751439446",
		"https://cdn.example.com/products/product-image-123.jpg",
		"https://cdn.example.com/dog-image.jpg",         // contains "og-image" but anchored start avoids it
		"https://cdn.example.com/casino-image.jpg",      // contains "no-image" but not at start
		"https://cdn.example.com/social-club-chair.jpg", // "social" token but not the social-image asset
	}
	for _, u := range keep {
		if IsNonProductImageURL(u) {
			t.Errorf("expected KEEP (product), got reject: %s", u)
		}
	}
}
