package application

import "testing"

func TestCachedExchangeConverterConvertsWithCachedRates(t *testing.T) {
	t.Parallel()

	converter := NewCachedExchangeConverter("", 0)
	converter.unitsPerEUR = map[string]float64{
		"EUR": 1,
		"USD": 1.25,
		"GBP": 0.8,
		"ILS": 4,
	}

	amount, currency, err := converter.Convert("100.00", "USD", "ILS")
	if err != nil {
		t.Fatalf("convert price: %v", err)
	}
	if amount != "320.00" || currency != "ILS" {
		t.Fatalf("expected 320.00 ILS, got %s %s", amount, currency)
	}
}

func TestCachedExchangeConverterFormatsZeroDecimalCurrency(t *testing.T) {
	t.Parallel()

	// JPY has no minor units; a converted amount must be a whole number, not
	// "1600.00".
	converter := NewCachedExchangeConverter("", 0)
	converter.unitsPerEUR = map[string]float64{"EUR": 1, "JPY": 160}

	amount, currency, err := converter.Convert("10", "EUR", "JPY")
	if err != nil {
		t.Fatalf("convert: %v", err)
	}
	if amount != "1600" || currency != "JPY" {
		t.Fatalf("expected 1600 JPY (zero decimals), got %s %s", amount, currency)
	}
}

func TestApplyRatesMergesAndDropsStale(t *testing.T) {
	t.Parallel()

	converter := NewCachedExchangeConverter("", 0)
	converter.unitsPerEUR = map[string]float64{"EUR": 1, "USD": 1.25}

	// A transient feed omission must NOT drop the prior rate (avoids a currency
	// going unconvertible for ~12h on one flaky refresh).
	converter.applyRates(map[string]float64{"EUR": 1})
	if converter.unitsPerEUR["USD"] != 1.25 {
		t.Fatalf("USD dropped after a single omission: %+v", converter.unitsPerEUR)
	}

	// After repeated consecutive omissions the (genuinely delisted) rate is dropped.
	converter.applyRates(map[string]float64{"EUR": 1})
	converter.applyRates(map[string]float64{"EUR": 1})
	if _, ok := converter.unitsPerEUR["USD"]; ok {
		t.Fatalf("USD should be dropped after repeated omissions: %+v", converter.unitsPerEUR)
	}

	// A returning rate is merged back in.
	converter.applyRates(map[string]float64{"EUR": 1, "USD": 1.30})
	if converter.unitsPerEUR["USD"] != 1.30 {
		t.Fatalf("USD not merged back: %+v", converter.unitsPerEUR)
	}
}

func TestParseECBRatesRequiresSupportedRates(t *testing.T) {
	t.Parallel()

	rates, err := parseECBRates([]byte(`
		<gesmes:Envelope>
			<Cube>
				<Cube time="2026-04-21">
					<Cube currency="USD" rate="1.25"/>
					<Cube currency="GBP" rate="0.8"/>
					<Cube currency="ILS" rate="4"/>
				</Cube>
			</Cube>
		</gesmes:Envelope>
	`))
	if err != nil {
		t.Fatalf("parse rates: %v", err)
	}
	if rates["EUR"] != 1 || rates["USD"] != 1.25 || rates["ILS"] != 4 {
		t.Fatalf("unexpected rates: %+v", rates)
	}
}
