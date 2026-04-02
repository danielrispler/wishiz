import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class Wishlist {
  Wishlist({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.description,
    required this.year,
    this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isArchived = false,
    this.isShared = false,
    List<SharedUser> sharedUsers = const [],
    List<WishlistItem> items = const [],
  })  : sharedUsers = List.unmodifiable(sharedUsers),
        items = List.unmodifiable(items);

  final String id;
  final String ownerUserId;
  final String title;
  final String description;
  final int year;
  final String? coverImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  final bool isShared;
  final List<SharedUser> sharedUsers;
  final List<WishlistItem> items;

  int get itemCount => items.length;
  List<WishlistItem> get activeItems => List.unmodifiable(
        items.where((item) => item.status != 'Purchased'),
      );
  List<WishlistItem> get purchasedItems => List.unmodifiable(
        items.where((item) => item.status == 'Purchased'),
      );
  int get activeItemCount => activeItems.length;
  int get purchasedItemCount => purchasedItems.length;

  Wishlist copyWith({
    String? id,
    String? ownerUserId,
    String? title,
    String? description,
    int? year,
    Object? coverImageUrl = _noValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
    bool? isShared,
    List<SharedUser>? sharedUsers,
    List<WishlistItem>? items,
  }) {
    return Wishlist(
      id: id ?? this.id,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      title: title ?? this.title,
      description: description ?? this.description,
      year: year ?? this.year,
      coverImageUrl: identical(coverImageUrl, _noValue)
          ? this.coverImageUrl
          : coverImageUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      isShared: isShared ?? this.isShared,
      sharedUsers: sharedUsers ?? this.sharedUsers,
      items: items ?? this.items,
    );
  }
}

const Object _noValue = Object();
