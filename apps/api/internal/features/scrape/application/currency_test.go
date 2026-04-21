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
