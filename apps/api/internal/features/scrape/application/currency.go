package application

import (
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

const defaultCurrencyCode = "USD"

// supportedCurrencyCodes is the set of currencies we can convert between. It is
// the ECB daily feed set (EUR base) — expanded beyond the original USD/EUR/GBP/
// ILS so scraped prices in these currencies are convertible rather than failed.
var supportedCurrencyCodes = map[string]struct{}{
	"USD": {}, "EUR": {}, "GBP": {}, "ILS": {},
	"CAD": {}, "AUD": {}, "JPY": {}, "CHF": {},
	"SEK": {}, "NOK": {}, "DKK": {}, "PLN": {}, "CZK": {},
}

func NormalizeCurrencyCode(code string) (string, error) {
	normalized := strings.ToUpper(strings.TrimSpace(code))
	if normalized == "" {
		normalized = defaultCurrencyCode
	}
	if _, ok := supportedCurrencyCodes[normalized]; !ok {
		return "", BadRequest("target currency is not supported")
	}
	return normalized, nil
}

type IdentityPriceConverter struct{}

func (IdentityPriceConverter) Convert(
	amount string, fromCurrency string, toCurrency string,
) (converted string, code string, err error) {
	from, err := NormalizeCurrencyCode(fromCurrency)
	if err != nil {
		return "", "", err
	}
	to, err := NormalizeCurrencyCode(toCurrency)
	if err != nil {
		return "", "", err
	}
	if from != to {
		return "", "", fmt.Errorf("exchange rate unavailable for %s to %s", from, to)
	}
	return amount, to, nil
}

type CachedExchangeConverter struct {
	client          *http.Client
	ratesURL        string
	refreshInterval time.Duration

	mu          sync.RWMutex
	unitsPerEUR map[string]float64
	// missCount tracks how many consecutive refreshes a previously-present
	// currency has been absent from the feed, so a transient omission doesn't
	// immediately drop a still-valid rate (see applyRates).
	missCount map[string]int
}

// maxStaleRefreshes is how many consecutive feed omissions a currency tolerates
// before its rate is dropped as genuinely delisted.
const maxStaleRefreshes = 3

// currencyMinorUnits overrides the default 2 decimals for currencies with a
// different minor-unit exponent. Only zero-decimal currencies need listing.
var currencyMinorUnits = map[string]int{
	"JPY": 0,
	"KRW": 0,
}

func NewCachedExchangeConverter(ratesURL string, refreshInterval time.Duration) *CachedExchangeConverter {
	if strings.TrimSpace(ratesURL) == "" {
		ratesURL = "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml"
	}
	if refreshInterval <= 0 {
		refreshInterval = 12 * time.Hour
	}

	return &CachedExchangeConverter{
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
		ratesURL:        ratesURL,
		refreshInterval: refreshInterval,
		unitsPerEUR: map[string]float64{
			"EUR": 1,
		},
	}
}

func (c *CachedExchangeConverter) Start(stop <-chan struct{}) {
	go func() {
		ticker := time.NewTicker(c.refreshInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				_ = c.Refresh()
			case <-stop:
				return
			}
		}
	}()
}

func (c *CachedExchangeConverter) Refresh() error {
	request, err := http.NewRequestWithContext(context.Background(), http.MethodGet, c.ratesURL, http.NoBody)
	if err != nil {
		return err
	}
	response, err := c.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusBadRequest {
		return fmt.Errorf("exchange rate source returned status %d", response.StatusCode)
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}

	rates, err := parseECBRates(body)
	if err != nil {
		return err
	}

	c.applyRates(rates)
	return nil
}

// applyRates merges a freshly-fetched rate set into the cache rather than
// replacing it wholesale: a currency the feed transiently omits keeps its prior
// rate for up to maxStaleRefreshes refreshes (so a single flaky feed doesn't make
// a currency unconvertible for ~12h), after which it is dropped as delisted.
func (c *CachedExchangeConverter) applyRates(rates map[string]float64) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.missCount == nil {
		c.missCount = map[string]int{}
	}
	for code, rate := range rates {
		c.unitsPerEUR[code] = rate
		delete(c.missCount, code)
	}
	for code := range c.unitsPerEUR {
		if code == "EUR" {
			continue // base is always present
		}
		if _, present := rates[code]; present {
			continue
		}
		c.missCount[code]++
		if c.missCount[code] >= maxStaleRefreshes {
			delete(c.unitsPerEUR, code)
			delete(c.missCount, code)
		}
	}
}

func (c *CachedExchangeConverter) Convert(
	amount string, fromCurrency string, toCurrency string,
) (amountOut string, codeOut string, err error) {
	from, err := NormalizeCurrencyCode(fromCurrency)
	if err != nil {
		return "", "", err
	}
	to, err := NormalizeCurrencyCode(toCurrency)
	if err != nil {
		return "", "", err
	}

	value, err := strconv.ParseFloat(strings.ReplaceAll(strings.TrimSpace(amount), ",", ""), 64)
	if err != nil || value <= 0 {
		return "", "", errors.New("price amount is not convertible")
	}

	if from == to {
		return formatPriceAmountFor(value, to), to, nil
	}

	c.mu.RLock()
	fromRate, hasFrom := c.unitsPerEUR[from]
	toRate, hasTo := c.unitsPerEUR[to]
	c.mu.RUnlock()

	if !hasFrom || !hasTo || fromRate <= 0 || toRate <= 0 {
		return "", "", fmt.Errorf("exchange rate unavailable for %s to %s", from, to)
	}

	eurAmount := value / fromRate
	converted := eurAmount * toRate
	return formatPriceAmountFor(converted, to), to, nil
}

// formatPriceAmountFor formats amount using code's minor-unit exponent (2 decimals
// by default, 0 for zero-decimal currencies like JPY). An empty code uses 2.
func formatPriceAmountFor(amount float64, code string) string {
	decimals := 2
	if d, ok := currencyMinorUnits[code]; ok {
		decimals = d
	}
	factor := math.Pow(10, float64(decimals))
	rounded := math.Round(amount*factor) / factor
	return strconv.FormatFloat(rounded, 'f', decimals, 64)
}

type ecbEnvelope struct {
	Rates []ecbRate `xml:"Cube>Cube>Cube"`
}

type ecbRate struct {
	Currency string `xml:"currency,attr"`
	Rate     string `xml:"rate,attr"`
}

func parseECBRates(payload []byte) (map[string]float64, error) {
	var envelope ecbEnvelope
	if err := xml.Unmarshal(payload, &envelope); err != nil {
		return nil, err
	}

	rates := map[string]float64{
		"EUR": 1,
	}

	for _, entry := range envelope.Rates {
		currency := strings.ToUpper(strings.TrimSpace(entry.Currency))
		if _, supported := supportedCurrencyCodes[currency]; !supported {
			continue
		}
		rate, err := strconv.ParseFloat(strings.TrimSpace(entry.Rate), 64)
		if err != nil || rate <= 0 {
			continue
		}
		rates[currency] = rate
	}

	// EUR is the base and always present. Do NOT require every supported code to
	// be in the feed: the moment supportedCurrencyCodes gains a code the ECB
	// omits, a strict check would fail every refresh and let rates go stale. Any
	// currency missing from the feed is simply not convertible (handled at
	// conversion time), which is safe.
	if _, ok := rates["EUR"]; !ok {
		return nil, errors.New("exchange rate feed missing EUR base")
	}

	return rates, nil
}
