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

	c.mu.Lock()
	c.unitsPerEUR = rates
	c.mu.Unlock()

	return nil
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
		return formatPriceAmount(value), to, nil
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
	return formatPriceAmount(converted), to, nil
}

func formatPriceAmount(amount float64) string {
	rounded := math.Round(amount*100) / 100
	return strconv.FormatFloat(rounded, 'f', 2, 64)
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
