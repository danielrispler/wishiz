import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/utils/currency_utils.dart';

void main() {
  group('CurrencyUtils', () {
    test('uses symbol icons for supported currencies', () {
      expect(CurrencyUtils.symbolFor('USD'), '\$');
      expect(CurrencyUtils.symbolFor('EUR'), '€');
      expect(CurrencyUtils.symbolFor('GBP'), '£');
      expect(CurrencyUtils.symbolFor('ILS'), '₪');
    });

    test('converts usd prices into euros', () {
      expect(
        CurrencyUtils.convertPriceLabel(
          '\$100',
          targetCurrencyCode: 'EUR',
        ),
        '€84.80',
      );
    });

    test('converts nis prices into pounds', () {
      expect(
        CurrencyUtils.convertPriceLabel(
          '₪314.63',
          targetCurrencyCode: 'GBP',
        ),
        '£73.84',
      );
    });

    test('parses code-based legacy labels', () {
      final parsed = CurrencyUtils.parsePriceLabel('EUR 120');

      expect(parsed?.currencyCode, 'EUR');
      expect(parsed?.amount, 120);
    });

    test('formats a converted price range across both bounds', () {
      expect(
        CurrencyUtils.formatRange(
          '579',
          '1598',
          fromCurrencyCode: 'USD',
          targetCurrencyCode: 'USD',
        ),
        '\$579 – \$1,598',
      );
      // Both bounds convert (USD → ILS at 3.1463): 100→314.63, 200→629.26.
      expect(
        CurrencyUtils.formatRange(
          '100',
          '200',
          fromCurrencyCode: 'USD',
          targetCurrencyCode: 'ILS',
        ),
        '₪314.63 – ₪629.26',
      );
    });

    test('formatRange collapses to a single amount when high is missing', () {
      expect(
        CurrencyUtils.formatRange('579', null,
            fromCurrencyCode: 'USD', targetCurrencyCode: 'USD'),
        '\$579',
      );
    });

    test('displayPrice shows a range only when a high bound is present', () {
      expect(
        CurrencyUtils.displayPrice(
          priceLabel: 'USD 579 – 1598',
          priceAmount: '579',
          priceAmountMax: '1598',
          priceCurrencyCode: 'USD',
          targetCurrencyCode: 'USD',
        ),
        '\$579 – \$1,598',
      );
      // No max → falls back to the scalar label path.
      expect(
        CurrencyUtils.displayPrice(
          priceLabel: '\$40',
          priceAmount: '40',
          priceAmountMax: null,
          priceCurrencyCode: 'USD',
          targetCurrencyCode: 'USD',
        ),
        '\$40',
      );
    });
  });
}
