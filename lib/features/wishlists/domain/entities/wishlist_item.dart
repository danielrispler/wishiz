class WishlistItem {
  const WishlistItem({
    required this.id,
    required this.title,
    this.notes,
    this.priceLabel,
    this.imageUrl,
    this.productUrl,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? notes;
  final String? priceLabel;
  final String? imageUrl;
  final String? productUrl;
  final DateTime createdAt;

  WishlistItem copyWith({
    String? id,
    String? title,
    Object? notes = _noValue,
    Object? priceLabel = _noValue,
    Object? imageUrl = _noValue,
    Object? productUrl = _noValue,
    DateTime? createdAt,
  }) {
    return WishlistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: identical(notes, _noValue) ? this.notes : notes as String?,
      priceLabel: identical(priceLabel, _noValue)
          ? this.priceLabel
          : priceLabel as String?,
      imageUrl: identical(imageUrl, _noValue)
          ? this.imageUrl
          : imageUrl as String?,
      productUrl: identical(productUrl, _noValue)
          ? this.productUrl
          : productUrl as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

const Object _noValue = Object();
