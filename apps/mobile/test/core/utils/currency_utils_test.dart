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
  });
}
