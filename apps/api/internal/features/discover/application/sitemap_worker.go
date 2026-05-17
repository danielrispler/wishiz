package application

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"log/slog"
	"math/rand"
	"net"
	"net/http"
	"net/url"
	"path"
	"sort"
	"strings"
	"sync"
	"time"

	utls "github.com/refraction-networking/utls"

	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/ports"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
)

const (
	defaultSitemapRefreshInterval = 24 * time.Hour
	minBrandSampleSize            = 10
	maxBrandSampleSize            = 15
	maxNestedSitemaps             = 24
	maxConcurrentSitemapFetches   = 4
	maxSitemapURLs                = 5000
	discoverFashionCategory       = "fashion"
)

var brandSitemaps = map[string]string{
	// High Street
	"Zara":             "https://www.zara.com/sitemap.xml",
	"H&M":              "https://www2.hm.com/sitemap.xml",
	"Mango":            "https://shop.mango.com/sitemap.xml",
	"ASOS":             "https://www.asos.com/sitemap.xml",
	"COS":              "https://www.cos.com/sitemap.xml",
	"Massimo Dutti":    "https://www.massimodutti.com/sitemap.xml",
	"Uniqlo":           "https://www.uniqlo.com/sitemap.xml",
	"Pull&Bear":        "https://www.pullandbear.com/sitemap.xml",
	"Stradivarius":     "https://www.stradivarius.com/sitemap.xml",
	"Urban Outfitters": "https://www.urbanoutfitters.com/sitemap.xml",
	"Old Navy":         "https://oldnavy.gap.com/sitemap.xml",
	"Terminal X":       "https://www.terminalx.com/sitemap.xml",

	// Activewear
	"Lululemon":             "https://shop.lululemon.com/sitemap.xml",
	"Alo Yoga":              "https://www.aloyoga.com/sitemap.xml",
	"Nike":                  "https://www.nike.com/sitemap.xml",
	"Adidas":                "https://www.adidas.com/sitemap.xml",
	"New Balance":           "https://www.newbalance.com/sitemap.xml",
	"Asics":                 "https://www.asics.com/sitemap.xml",
	"Under Armour":          "https://www.underarmour.com/sitemap.xml",
	"Gymshark":              "https://www.gymshark.com/sitemap.xml",
	"Set Active":            "https://setactive.co/sitemap.xml",
	"Oysho":                 "https://www.oysho.com/sitemap.xml",
	"Girlfriend Collective": "https://girlfriend.com/sitemap.xml",
	"Bandit":                "https://banditrunning.com/sitemap.xml",
	"CRZ Yoga":              "https://crzyoga.com/sitemap.xml",

	// Premium
	"Revolve":       "https://www.revolve.com/sitemap.xml",
	"Reformation":   "https://www.thereformation.com/sitemap.xml",
	"Aritzia":       "https://www.aritzia.com/sitemap.xml",
	"Shopbop":       "https://www.shopbop.com/sitemap.xml",
	"Anthropologie": "https://www.anthropologie.com/sitemap.xml",
	"Nordstrom":     "https://www.nordstrom.com/sitemap.xml",
	"Factory 54":    "https://www.factory54.co.il/sitemap.xml",
	"Story":         "https://www.storyonline.co.il/sitemap.xml",
	"De Rococo":     "https://derococo.com/sitemap.xml",

	// Intimates & Lounge
	"Skims":             "https://skims.com/sitemap.xml",
	"Victoria's Secret": "https://www.victoriassecret.com/sitemap.xml",
	"Aerie":             "https://www.ae.com/sitemap.xml",
	"Intimissimi":       "https://www.intimissimi.com/sitemap.xml",

	// Denim & Niche
	"Levi's":        "https://www.levi.com/sitemap.xml",
	"Pistola":       "https://pistoladenim.com/sitemap.xml",
	"Eloquii":       "https://www.eloquii.com/sitemap.xml",
	"Good American": "https://www.goodamerican.com/sitemap.xml",
}

type SitemapWorker struct {
	logger          *slog.Logger
	repo            ports.Repository
	scrapeService   *scrapeapp.Service
	httpClient      *http.Client
	refreshInterval time.Duration
	rng             *rand.Rand
	brands          []sitemapBrand
}

type sitemapBrand struct {
	Name           string
	SitemapURL     string
	AllowedDomains []string
	ProductHints   []string
}

type sitemapURLSet struct {
	URLs     []sitemapEntry `xml:"url"`
	Sitemaps []sitemapEntry `xml:"sitemap"`
}

type sitemapEntry struct {
	Loc string `xml:"loc"`
}

func (s sitemapURLSet) locs() []string {
	out := make([]string, 0, len(s.URLs)+len(s.Sitemaps))
	for _, u := range s.URLs {
		if u.Loc != "" {
			out = append(out, u.Loc)
		}
	}
	for _, sm := range s.Sitemaps {
		if sm.Loc != "" {
			out = append(out, sm.Loc)
		}
	}
	return out
}

func NewSitemapWorker(
	logger *slog.Logger,
	repo ports.Repository,
	scrapeService *scrapeapp.Service,
	refreshInterval time.Duration,
) *SitemapWorker {
	if logger == nil {
		logger = slog.Default()
	}
	if refreshInterval <= 0 {
		refreshInterval = defaultSitemapRefreshInterval
	}
	return &SitemapWorker{
		logger:        logger,
		repo:          repo,
		scrapeService: scrapeService,
		httpClient: &http.Client{
			Timeout:   20 * time.Second,
			Transport: newUTLSTransport(),
		},
		refreshInterval: refreshInterval,
		rng:             rand.New(rand.NewSource(time.Now().UnixNano())), //nolint:gosec
		brands:          defaultSitemapBrands(),
	}
}

func (w *SitemapWorker) Start(ctx context.Context) {
	go func() {
		w.run(ctx)
	}()
}

func (w *SitemapWorker) run(ctx context.Context) {
	w.refresh(ctx)

	ticker := time.NewTicker(w.refreshInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.refresh(ctx)
		}
	}
}

func (w *SitemapWorker) refresh(ctx context.Context) {
	startedAt := time.Now()
	totalInserted := 0

	for _, brand := range w.brands {
		inserted, err := w.refreshBrand(ctx, brand)
		if err != nil {
			w.logger.Warn("Failed to process sitemap for "+brand.Name, "sitemap_url", brand.SitemapURL, "error", err)
			continue
		}
		totalInserted += inserted
	}

	w.logger.Info(
		"discover sitemap refresh finished",
		"brands", len(w.brands),
		"products_upserted", totalInserted,
		"duration_ms", time.Since(startedAt).Milliseconds(),
	)
}

func (w *SitemapWorker) refreshBrand(ctx context.Context, brand sitemapBrand) (int, error) {
	urls, err := w.collectSitemapURLs(ctx, brand.SitemapURL, 0)
	if err != nil {
		return 0, err
	}
	candidates := filterProductURLs(urls, brand)
	if len(candidates) == 0 {
		return 0, fmt.Errorf("no product urls found in sitemap %s", brand.SitemapURL)
	}

	sampleSize := minBrandSampleSize
	if len(candidates) > minBrandSampleSize {
		sampleSize = minBrandSampleSize + w.rng.Intn(maxBrandSampleSize-minBrandSampleSize+1)
	}
	if sampleSize > len(candidates) {
		sampleSize = len(candidates)
	}

	w.rng.Shuffle(len(candidates), func(i, j int) {
		candidates[i], candidates[j] = candidates[j], candidates[i]
	})
	selected := candidates[:sampleSize]

	inserted := 0
	for index, productURL := range selected {
		if index > 0 {
			select {
			case <-ctx.Done():
				return inserted, ctx.Err()
			case <-time.After(2 * time.Second):
			}
		}

		cleanURL, sanitizeErr := sanitizeProductURL(productURL)
		if sanitizeErr != nil {
			w.logger.Warn("discover url sanitize failed", "brand", brand.Name, "url", productURL, "error", sanitizeErr)
			continue
		}

		product, err := w.scrapeService.Scrape(ctx, cleanURL, "USD")
		if err != nil && product.Name == "" && product.ImageURL == "" {
			w.logger.Warn("discover scrape failed", "brand", brand.Name, "url", cleanURL, "error", err)
			continue
		}
		if strings.TrimSpace(product.Name) == "" || strings.TrimSpace(product.ImageURL) == "" {
			continue
		}

		var priceLabel *string
		if product.PriceAmount != "" && product.PriceConfidence != scrapeapp.PriceConfidenceSuspicious {
			label := product.PriceAmount
			if product.PriceCurrency != "" {
				label = product.PriceCurrency + " " + product.PriceAmount
			}
			priceLabel = &label
		}

		gender, productType := extractProductMeta(cleanURL, product.Name)

		_, err = w.repo.SeedProduct(ctx, ports.SeedProductInput{
			Title:       strings.TrimSpace(product.Name),
			Brand:       brand.Name,
			Category:    discoverFashionCategory,
			ImageURL:    strings.TrimSpace(product.ImageURL),
			ProductURL:  stringPtr(cleanURL),
			PriceLabel:  priceLabel,
			Gender:      gender,
			ProductType: productType,
		})
		if err != nil {
			w.logger.Warn("discover seed failed", "brand", brand.Name, "url", productURL, "error", err)
			continue
		}
		inserted++
	}

	return inserted, nil
}

func (w *SitemapWorker) collectSitemapURLs(ctx context.Context, sitemapURL string, depth int) ([]string, error) {
	if depth > maxNestedSitemaps {
		return nil, fmt.Errorf("sitemap recursion limit exceeded for %s", sitemapURL)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sitemapURL, nil)
	if err != nil {
		return nil, fmt.Errorf("build sitemap request: %w", err)
	}

	resp, err := w.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch sitemap %s: %w", sitemapURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fetch sitemap %s: unexpected status %d", sitemapURL, resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, fmt.Errorf("read sitemap %s: %w", sitemapURL, err)
	}

	var parsed sitemapURLSet
	if err := xml.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("parse sitemap %s: %w", sitemapURL, err)
	}

	locs := uniqueStrings(parsed.locs())
	if len(locs) == 0 {
		return nil, nil
	}

	// Sitemap indexes also expose child sitemap URLs through <loc>. Detect them heuristically and recurse.
	if allLookLikeSitemaps(locs) {
		var (
			mu      sync.Mutex
			results []string
			wg      sync.WaitGroup
		)
		sem := make(chan struct{}, maxConcurrentSitemapFetches)
		for _, childURL := range locs {
			sem <- struct{}{}
			wg.Add(1)
			go func(u string) {
				defer func() { <-sem }()
				defer wg.Done()
				childURLs, childErr := w.collectSitemapURLs(ctx, u, depth+1)
				if childErr != nil {
					w.logger.Debug("nested sitemap fetch failed", "url", u, "error", childErr)
					return
				}
				mu.Lock()
				results = append(results, childURLs...)
				if len(results) > maxSitemapURLs {
					results = results[:maxSitemapURLs]
				}
				mu.Unlock()
			}(childURL)
		}
		wg.Wait()
		return uniqueStrings(results), nil
	}

	if len(locs) > maxSitemapURLs {
		locs = locs[:maxSitemapURLs]
	}
	return locs, nil
}

func defaultSitemapBrands() []sitemapBrand {
	brands := make([]sitemapBrand, 0, len(brandSitemaps))
	names := make([]string, 0, len(brandSitemaps))
	for name := range brandSitemaps {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		sitemapURL := brandSitemaps[name]
		domain := sitemapDomain(sitemapURL)
		brands = append(brands, sitemapBrand{
			Name:           name,
			SitemapURL:     sitemapURL,
			AllowedDomains: []string{domain},
			ProductHints: []string{
				"/product/",
				"/products/",
				"/prd/",
				"/p/",
				"/t/",
				"-p",
				"product",
			},
		})
	}
	return brands
}

func sitemapDomain(rawURL string) string {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return parsed.Hostname()
}

func filterProductURLs(urls []string, brand sitemapBrand) []string {
	filtered := make([]string, 0, len(urls))
	for _, raw := range urls {
		u, err := url.Parse(raw)
		if err != nil {
			continue
		}
		if !matchesDomain(u.Hostname(), brand.AllowedDomains) {
			continue
		}
		if !looksLikeProductURL(u, brand.ProductHints) {
			continue
		}
		filtered = append(filtered, raw)
	}
	return uniqueStrings(filtered)
}

func matchesDomain(host string, allowed []string) bool {
	host = strings.ToLower(strings.TrimSpace(host))
	for _, domain := range allowed {
		domain = strings.ToLower(strings.TrimSpace(domain))
		if host == domain || strings.HasSuffix(host, "."+domain) {
			return true
		}
	}
	return false
}

func looksLikeProductURL(u *url.URL, hints []string) bool {
	p := strings.ToLower(u.EscapedPath())
	base := strings.ToLower(path.Base(p))
	for _, hint := range hints {
		if strings.Contains(p, strings.ToLower(hint)) || strings.Contains(base, strings.ToLower(hint)) {
			return true
		}
	}
	// Fallback: product detail pages usually have a deep path and a slug-like leaf.
	if strings.Count(strings.Trim(p, "/"), "/") >= 1 && strings.Contains(base, "-") {
		return true
	}
	return false
}

func allLookLikeSitemaps(urls []string) bool {
	for _, raw := range urls {
		if !strings.Contains(strings.ToLower(raw), "sitemap") && !strings.HasSuffix(strings.ToLower(raw), ".xml") {
			return false
		}
	}
	return true
}

func uniqueStrings(items []string) []string {
	seen := make(map[string]struct{}, len(items))
	out := make([]string, 0, len(items))
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if _, ok := seen[item]; ok {
			continue
		}
		seen[item] = struct{}{}
		out = append(out, item)
	}
	return out
}

func stringPtr(value string) *string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	v := value
	return &v
}

func newUTLSTransport() *http.Transport {
	return &http.Transport{
		ForceAttemptHTTP2: false,
		DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			conn, err := net.DialTimeout(network, addr, 10*time.Second)
			if err != nil {
				return nil, err
			}
			host, _, _ := net.SplitHostPort(addr)
			uConn := utls.UClient(conn, &utls.Config{ServerName: host}, utls.HelloChrome_Auto)

			if err := uConn.BuildHandshakeState(); err != nil {
				conn.Close()
				return nil, err
			}

			// Strip "h2" from ALPN to force HTTP/1.1 and prevent the framing mismatch
			for _, ext := range uConn.Extensions {
				if alpn, ok := ext.(*utls.ALPNExtension); ok {
					alpn.AlpnProtocols = []string{"http/1.1"}
					break
				}
			}

			if err := uConn.HandshakeContext(ctx); err != nil {
				conn.Close()
				return nil, err
			}
			return uConn, nil
		},
	}
}

func sanitizeProductURL(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if u.Scheme == "" {
		u.Scheme = "https"
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return "", fmt.Errorf("url must use http or https: %s", raw)
	}
	return u.String(), nil
}

func extractProductMeta(productURL, title string) (gender, productType *string) {
	combined := strings.ToLower(productURL + " " + title)
	urlLower := strings.ToLower(productURL)

	maleKW := []string{"/men/", "-men-", "mens", "/boy", "male"}
	femaleKW := []string{"/women/", "-women-", "womens", "/girl", "female"}
	for _, kw := range maleKW {
		if strings.Contains(combined, kw) {
			g := "Men"
			gender = &g
			break
		}
	}
	if gender == nil {
		for _, kw := range femaleKW {
			if strings.Contains(combined, kw) {
				g := "Women"
				gender = &g
				break
			}
		}
	}

	typeMap := map[string]string{
		"/shoes/":    "Shoes",
		"/bags/":     "Bags",
		"/pants/":    "Pants",
		"/dresses/":  "Dresses",
		"/tops/":     "Tops",
		"/jackets/":  "Jackets",
		"/skirts/":   "Skirts",
		"/shorts/":   "Shorts",
		"/swimwear/": "Swimwear",
		"/lingerie/": "Lingerie",
		"/jeans/":    "Jeans",
		"/coats/":    "Coats",
	}
	for kw, pt := range typeMap {
		if strings.Contains(urlLower, kw) {
			p := pt
			productType = &p
			break
		}
	}
	return
}
