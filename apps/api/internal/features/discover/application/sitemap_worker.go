package application

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"log/slog"
	"math/rand"
	"net/http"
	"net/url"
	"path"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/danielrispler/wishiz/apps/api/internal/features/discover/ports"
	scrapeapp "github.com/danielrispler/wishiz/apps/api/internal/features/scrape/application"
	"github.com/danielrispler/wishiz/apps/api/internal/platform/httpx"
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

// brandSource describes a discovery source site: where to find its sitemap and
// which discover category its products belong to.
type brandSource struct {
	SitemapURL string
	Category   string // discover category; "" defaults to fashion
}

var brandSitemaps = map[string]brandSource{
	// High Street
	"Zara":             {SitemapURL: "https://www.zara.com/sitemap.xml"},
	"H&M":              {SitemapURL: "https://www2.hm.com/sitemap.xml"},
	"Mango":            {SitemapURL: "https://shop.mango.com/sitemap.xml"},
	"ASOS":             {SitemapURL: "https://www.asos.com/sitemap.xml"},
	"COS":              {SitemapURL: "https://www.cos.com/sitemap.xml"},
	"Massimo Dutti":    {SitemapURL: "https://www.massimodutti.com/sitemap.xml"},
	"Uniqlo":           {SitemapURL: "https://www.uniqlo.com/sitemap.xml"},
	"Pull&Bear":        {SitemapURL: "https://www.pullandbear.com/sitemap.xml"},
	"Stradivarius":     {SitemapURL: "https://www.stradivarius.com/sitemap.xml"},
	"Urban Outfitters": {SitemapURL: "https://www.urbanoutfitters.com/sitemap.xml"},
	"Old Navy":         {SitemapURL: "https://oldnavy.gap.com/sitemap.xml"},
	"Terminal X":       {SitemapURL: "https://www.terminalx.com/sitemap.xml"},

	// Activewear
	"Lululemon":             {SitemapURL: "https://shop.lululemon.com/sitemap.xml"},
	"Alo Yoga":              {SitemapURL: "https://www.aloyoga.com/sitemap.xml"},
	"Nike":                  {SitemapURL: "https://www.nike.com/sitemap.xml"},
	"Adidas":                {SitemapURL: "https://www.adidas.com/sitemap.xml"},
	"New Balance":           {SitemapURL: "https://www.newbalance.com/sitemap.xml"},
	"Asics":                 {SitemapURL: "https://www.asics.com/sitemap.xml"},
	"Under Armour":          {SitemapURL: "https://www.underarmour.com/sitemap.xml"},
	"Gymshark":              {SitemapURL: "https://www.gymshark.com/sitemap.xml"},
	"Set Active":            {SitemapURL: "https://setactive.co/sitemap.xml"},
	"Oysho":                 {SitemapURL: "https://www.oysho.com/sitemap.xml"},
	"Girlfriend Collective": {SitemapURL: "https://girlfriend.com/sitemap.xml"},
	"Bandit":                {SitemapURL: "https://banditrunning.com/sitemap.xml"},
	"CRZ Yoga":              {SitemapURL: "https://crzyoga.com/sitemap.xml"},

	// Premium
	"Revolve":       {SitemapURL: "https://www.revolve.com/sitemap.xml"},
	"Reformation":   {SitemapURL: "https://www.thereformation.com/sitemap.xml"},
	"Aritzia":       {SitemapURL: "https://www.aritzia.com/sitemap.xml"},
	"Shopbop":       {SitemapURL: "https://www.shopbop.com/sitemap.xml"},
	"Anthropologie": {SitemapURL: "https://www.anthropologie.com/sitemap.xml"},
	"Nordstrom":     {SitemapURL: "https://www.nordstrom.com/sitemap.xml"},
	"Factory 54":    {SitemapURL: "https://www.factory54.co.il/sitemap.xml"},
	"Story":         {SitemapURL: "https://www.storyonline.co.il/sitemap.xml"},
	"De Rococo":     {SitemapURL: "https://derococo.com/sitemap.xml"},

	// Intimates & Lounge
	"Skims":             {SitemapURL: "https://skims.com/sitemap.xml"},
	"Victoria's Secret": {SitemapURL: "https://www.victoriassecret.com/sitemap.xml"},
	"Aerie":             {SitemapURL: "https://www.ae.com/sitemap.xml"},
	"Intimissimi":       {SitemapURL: "https://www.intimissimi.com/sitemap.xml"},

	// Denim & Niche
	"Levi's":         {SitemapURL: "https://www.levi.com/sitemap.xml"},
	"Pistola":        {SitemapURL: "https://pistoladenim.com/sitemap.xml"},
	"Eloquii":        {SitemapURL: "https://www.eloquii.com/sitemap.xml"},
	"Good American":  {SitemapURL: "https://www.goodamerican.com/sitemap.xml"},
	"nars":           {SitemapURL: "https://www.narscosmetics.co.il/sitemap.xml"},
	"brandymelville": {SitemapURL: "https://us.brandymelville.com/sitemap.xml"},

	// Contemporary & designer (sitemap verified 2026-06-20)
	"Vuori":                {SitemapURL: "https://vuoriclothing.com/sitemap.xml"},
	"Agolde":               {SitemapURL: "https://agolde.com/sitemap.xml"},
	"Citizens of Humanity": {SitemapURL: "https://citizensofhumanity.com/sitemap.xml"},
	"Zadig & Voltaire":     {SitemapURL: "https://www.zadig-et-voltaire.com/sitemap.xml"},
	"Totême":               {SitemapURL: "https://toteme-studio.com/sitemap.xml"},
	"Leset":                {SitemapURL: "https://leset.com/sitemap.xml"},
	"Sézane":               {SitemapURL: "https://www.sezane.com/sitemap.xml"},
	"Rouje":                {SitemapURL: "https://www.rouje.com/sitemap.xml"},
	"Damson Madder":        {SitemapURL: "https://damsonmadder.com/sitemap.xml"},
	"A.P.C.":               {SitemapURL: "https://www.apc-us.com/sitemap.xml"},
	"A.L.C.":               {SitemapURL: "https://www.alcltd.com/sitemap.xml"},
	"Anine Bing":           {SitemapURL: "https://www.aninebing.com/sitemap.xml"},
	"Staud":                {SitemapURL: "https://staud.clothing/sitemap.xml"},
	"Tory Burch":           {SitemapURL: "https://www.toryburch.com/sitemap.xml"},
	"Miu Miu":              {SitemapURL: "https://www.miumiu.com/sitemap.xml"},
	"Prada":                {SitemapURL: "https://www.prada.com/sitemap.xml"},
	"Isabel Marant":        {SitemapURL: "https://www.isabelmarant.com/sitemap.xml"},
	"Still Here":           {SitemapURL: "https://www.stillhere.nyc/sitemap.xml"},

	// sitemap_index.xml (verified 200)
	"Rag & Bone":      {SitemapURL: "https://www.rag-bone.com/sitemap_index.xml"},
	"Vince":           {SitemapURL: "https://www.vince.com/sitemap_index.xml"},
	"Theory":          {SitemapURL: "https://www.theory.com/sitemap_index.xml"},
	"Maison Margiela": {SitemapURL: "https://www.maisonmargiela.com/sitemap_index.xml"},
	"Ganni":           {SitemapURL: "https://www.ganni.com/sitemap_index.xml"},
	"Maje":            {SitemapURL: "https://us.maje.com/sitemap_index.xml"},
	"Sandro":          {SitemapURL: "https://us.sandro-paris.com/sitemap_index.xml"},

	// Locale-specific sitemap index (verified 200)
	"Golden Goose": {SitemapURL: "https://www.goldengoose.com/us/en/sitemap_index.xml"},
	"Marni":        {SitemapURL: "https://www.marni.com/en-gb/sitemap_index.xml"},
	"Loewe":        {SitemapURL: "https://www.loewe.com/usa/en/sitemap_index.xml"},
	"Chloé":        {SitemapURL: "https://www.chloe.com/en-us/sitemap_index.xml"},

	// Best-effort: bot-blocked to plain curl, may pass via the utls Chrome
	// transport. Non-fatal if not — the worker logs a warning and skips.
	"Polo Ralph Lauren": {SitemapURL: "https://www.ralphlauren.com/sitemap_index.xml"},
	"The RealReal":      {SitemapURL: "https://www.therealreal.com/sitemaps/sitemap_index.xml"},
	"Coach":             {SitemapURL: "https://www.coach.com/sitemap_index.xml"},
	"Ba&sh":             {SitemapURL: "https://us.ba-sh.com/sitemap.xml"},

	// Beauty
	"Le Labo":  {SitemapURL: "https://www.lelabofragrances.com/sitemap.xml", Category: "beauty"},
	"Aesop":    {SitemapURL: "https://www.aesop.com/sitemap_index.xml", Category: "beauty"},
	"Diptyque": {SitemapURL: "https://www.diptyqueparis.com/media/sitemap_en_us.xml", Category: "beauty"},

	// Home
	"West Elm":       {SitemapURL: "https://www.westelm.com/sitemap.xml", Category: "home"},
	"Crate & Barrel": {SitemapURL: "https://www.crateandbarrel.com/sitemap.xml", Category: "home"},
	"Pottery Barn":   {SitemapURL: "https://www.potterybarn.com/sitemap.xml", Category: "home"},
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
	Category       string
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
			Transport: httpx.NewUTLSTransport(10 * time.Second),
		},
		refreshInterval: refreshInterval,
		rng:             rand.New(rand.NewSource(time.Now().UnixNano())), //nolint:gosec // jitter only, not security-sensitive
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

		// Discover MUST use Scrape (own pipeline only) and never ScrapeImport: only the
		// import path triggers the paid ZenRows backstop. Keep this call on Scrape.
		product, err := w.scrapeService.Scrape(ctx, cleanURL, "USD")
		if err != nil && product.Name == "" && product.ImageURL == "" {
			w.logger.Warn("discover scrape failed", "brand", brand.Name, "url", cleanURL, "error", err)
			continue
		}
		// Only seed products the scraper is sure about (auto_complete + name + image).
		if !isSeedable(product) {
			w.logger.Debug(
				"discover scrape not confident, skipping",
				"brand", brand.Name, "url", cleanURL, "verdict", string(product.Verdict),
			)
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
			Category:    brand.Category,
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

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sitemapURL, http.NoBody)
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
		src := brandSitemaps[name]
		category := src.Category
		if category == "" {
			category = discoverFashionCategory
		}
		domain := sitemapDomain(src.SitemapURL)
		brands = append(brands, sitemapBrand{
			Name:           name,
			SitemapURL:     src.SitemapURL,
			Category:       category,
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
			g := "men"
			gender = &g
			break
		}
	}
	if gender == nil {
		for _, kw := range femaleKW {
			if strings.Contains(combined, kw) {
				g := "women"
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
