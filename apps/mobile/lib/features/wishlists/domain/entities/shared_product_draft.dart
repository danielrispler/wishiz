class SharedProductDraft {
  const SharedProductDraft({
    required this.productUrl,
    this.title,
    this.notes,
    this.priceLabel,
    this.imageUrl,
    this.sharedText,
  });

  final String productUrl;
  final String? title;
  final String? notes;
  final String? priceLabel;
  final String? imageUrl;
  final String? sharedText;

  bool get hasCompleteRequiredFields =>
      _hasValue(title) && _hasValue(priceLabel) && _hasValue(imageUrl);

  bool get isMissingTitle => !_hasValue(title);
  bool get isMissingPrice => !_hasValue(priceLabel);
  bool get isMissingImage => !_hasValue(imageUrl);

  List<String> get missingFieldLabels {
    final fields = <String>[];
    if (isMissingTitle) {
      fields.add('title');
    }
    if (isMissingPrice) {
      fields.add('price');
    }
    if (isMissingImage) {
      fields.add('image');
    }
    return List<String>.unmodifiable(fields);
  }

  SharedProductDraft copyWith({
    String? productUrl,
    Object? title = _noValue,
    Object? notes = _noValue,
    Object? priceLabel = _noValue,
    Object? imageUrl = _noValue,
    Object? sharedText = _noValue,
  }) {
    return SharedProductDraft(
      productUrl: productUrl ?? this.productUrl,
      title: identical(title, _noValue) ? this.title : title as String?,
      notes: identical(notes, _noValue) ? this.notes : notes as String?,
      priceLabel: identical(priceLabel, _noValue)
          ? this.priceLabel
          : priceLabel as String?,
      imageUrl:
          identical(imageUrl, _noValue) ? this.imageUrl : imageUrl as String?,
      sharedText: identical(sharedText, _noValue)
          ? this.sharedText
          : sharedText as String?,
    );
  }

  static bool _hasValue(String? value) =>
      value != null && value.trim().isNotEmpty;
}

const Object _noValue = Object();
