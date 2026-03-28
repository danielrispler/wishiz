class CurrencyUtils {
  CurrencyUtils._();

  static const Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'ILS': '₪',
  };

  static const Map<String, double> _unitsPerUsd = {
    'USD': 1,
    'EUR': 0.8480,
    'GBP': 0.7384,
    'ILS': 3.1463,
  };

  static String symbolFor(String currencyCode) {
    return currencySymbols[currencyCode] ?? '$currencyCode ';
  }

  static String? convertPriceLabel(
    String? priceLabel, {
    required String targetCurrencyCode,
  }) {
    final trimmed = priceLabel?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final parsed = parsePriceLabel(trimmed);
    if (parsed == null) {
      return trimmed;
    }

    final convertedAmount = convertAmount(
      parsed.amount,
      fromCurrencyCode: parsed.currencyCode,
      toCurrencyCode: targetCurrencyCode,
    );
    return formatAmount(convertedAmount, targetCurrencyCode);
  }

  static ParsedCurrencyAmount? parsePriceLabel(String? priceLabel) {
    final trimmed = priceLabel?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }

    final currencyCode = _detectCurrencyCode(trimmed);
    final amountMatch = RegExp(r'(\d[\d,]*(?:[.]\d+)?)').firstMatch(trimmed);
    final amountText = amountMatch?.group(1)?.replaceAll(',', '');
    if (amountText == null) {
      return null;
    }

    final amount = double.tryParse(amountText);
    if (amount == null) {
      return null;
    }

    return ParsedCurrencyAmount(
      currencyCode: currencyCode,
      amount: amount,
    );
  }

  static double convertAmount(
    double amount, {
    required String fromCurrencyCode,
    required String toCurrencyCode,
  }) {
    if (fromCurrencyCode == toCurrencyCode) {
      return amount;
    }

    final fromRate = _unitsPerUsd[fromCurrencyCode];
    final toRate = _unitsPerUsd[toCurrencyCode];
    if (fromRate == null || toRate == null) {
      return amount;
    }

    final usdAmount = amount / fromRate;
    return usdAmount * toRate;
  }

  static String formatAmount(double amount, String currencyCode) {
    final roundedAmount = amount.roundToDouble();
    final useWholeNumber = (amount - roundedAmount).abs() < 0.005;
    final amountText = useWholeNumber
        ? _addThousandsSeparators(roundedAmount.toInt().toString())
        : _addThousandsSeparators(amount.toStringAsFixed(2));
    return '${symbolFor(currencyCode)}$amountText';
  }

  static String _detectCurrencyCode(String priceLabel) {
    final normalized = priceLabel.trim().toUpperCase();

    if (normalized.startsWith('€') || normalized.startsWith('EUR')) {
      return 'EUR';
    }
    if (normalized.startsWith('£') || normalized.startsWith('GBP')) {
      return 'GBP';
    }
    if (normalized.startsWith('₪') ||
        normalized.startsWith('ILS') ||
        normalized.startsWith('NIS')) {
      return 'ILS';
    }
    return 'USD';
  }

  static String _addThousandsSeparators(String amountText) {
    final parts = amountText.split('.');
    final wholePart = parts.first;
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';
    final formattedWhole = wholePart.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$formattedWhole$decimalPart';
  }
}

class ParsedCurrencyAmount {
  const ParsedCurrencyAmount({
    required this.currencyCode,
    required this.amount,
  });

  final String currencyCode;
  final double amount;
}
