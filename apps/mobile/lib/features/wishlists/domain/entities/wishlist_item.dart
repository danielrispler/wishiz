import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';

class WishlistItem {
  const WishlistItem({
    required this.id,
    required this.title,
    required this.rank,
    this.notes,
    this.priceLabel,
    this.priceAmount,
    this.priceAmountMax,
    this.priceCurrencyCode,
    this.priority = WishlistItemPriority.medium,
    this.status = WishlistItemStatus.saved,
    this.imageUrl,
    this.productUrl,
    this.purchasedAt,
    required this.createdAt,
  });

  static const List<WishlistItemPriority> priorities =
      WishlistItemPriority.values;
  static const List<WishlistItemStatus> statuses = WishlistItemStatus.values;

  final String id;
  final String title;
  final int rank;
  final String? notes;
  final String? priceLabel;

  /// Structured price for range-aware display. priceAmount is the low/"starting"
  /// bound; priceAmountMax is the high bound (non-null only for a range). Both are in
  /// priceCurrencyCode and converted to the viewing user's currency at display.
  /// Editing the price clears these (the item collapses to the scalar priceLabel).
  final String? priceAmount;
  final String? priceAmountMax;
  final String? priceCurrencyCode;
  final WishlistItemPriority priority;
  final WishlistItemStatus status;
  final String? imageUrl;
  final String? productUrl;
  final DateTime? purchasedAt;
  final DateTime createdAt;

  int get daysOnList {
    final days = DateTime.now().difference(createdAt).inDays;
    return days < 0 ? 0 : days;
  }

  WishlistItem copyWith({
    String? id,
    String? title,
    int? rank,
    Object? notes = _noValue,
    Object? priceLabel = _noValue,
    Object? priceAmount = _noValue,
    Object? priceAmountMax = _noValue,
    Object? priceCurrencyCode = _noValue,
    WishlistItemPriority? priority,
    WishlistItemStatus? status,
    Object? imageUrl = _noValue,
    Object? productUrl = _noValue,
    Object? purchasedAt = _noValue,
    DateTime? createdAt,
  }) {
    return WishlistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      rank: rank ?? this.rank,
      notes: identical(notes, _noValue) ? this.notes : notes as String?,
      priceLabel: identical(priceLabel, _noValue)
          ? this.priceLabel
          : priceLabel as String?,
      priceAmount: identical(priceAmount, _noValue)
          ? this.priceAmount
          : priceAmount as String?,
      priceAmountMax: identical(priceAmountMax, _noValue)
          ? this.priceAmountMax
          : priceAmountMax as String?,
      priceCurrencyCode: identical(priceCurrencyCode, _noValue)
          ? this.priceCurrencyCode
          : priceCurrencyCode as String?,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      imageUrl: identical(imageUrl, _noValue)
          ? this.imageUrl
          : imageUrl as String?,
      productUrl: identical(productUrl, _noValue)
          ? this.productUrl
          : productUrl as String?,
      purchasedAt: identical(purchasedAt, _noValue)
          ? this.purchasedAt
          : purchasedAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

const Object _noValue = Object();
