import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class Wishlist {
  Wishlist({
    required this.id,
    required this.title,
    required this.description,
    this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.isShared = false,
    List<WishlistItem> items = const [],
  }) : items = List.unmodifiable(items);

  final String id;
  final String title;
  final String description;
  final String? coverImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  final bool isShared;
  final List<WishlistItem> items;

  int get itemCount => items.length;

  Wishlist copyWith({
    String? id,
    String? title,
    String? description,
    Object? coverImageUrl = _noValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
    bool? isShared,
    List<WishlistItem>? items,
  }) {
    return Wishlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      coverImageUrl: identical(coverImageUrl, _noValue)
          ? this.coverImageUrl
          : coverImageUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      isShared: isShared ?? this.isShared,
      items: items ?? this.items,
    );
  }
}

const Object _noValue = Object();
