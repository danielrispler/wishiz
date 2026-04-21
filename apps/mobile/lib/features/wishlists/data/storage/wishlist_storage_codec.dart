import 'dart:convert';

import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class WishlistStorageCodec {
  const WishlistStorageCodec();

  String encode(List<Wishlist> wishlists) {
    return jsonEncode(
      wishlists.map(_wishlistToJson).toList(growable: false),
    );
  }

  List<Wishlist> decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Expected a wishlist array.');
    }

    return decoded
        .map((wishlist) => _wishlistFromJson(wishlist as Map<String, dynamic>))
        .toList(growable: false);
  }

  Map<String, Object?> _wishlistToJson(Wishlist wishlist) {
    return {
      'id': wishlist.id,
      'ownerUserId': wishlist.ownerUserId,
      'title': wishlist.title,
      'description': wishlist.description,
      'year': wishlist.year,
      'coverImageUrl': wishlist.coverImageUrl,
      'createdAt': wishlist.createdAt.toIso8601String(),
      'updatedAt': wishlist.updatedAt.toIso8601String(),
      'isArchived': wishlist.isArchived,
      'sharedUsers':
          wishlist.sharedUsers.map(_sharedUserToJson).toList(growable: false),
      'items': wishlist.items.map(_itemToJson).toList(growable: false),
    };
  }

  Wishlist _wishlistFromJson(Map<String, dynamic> json) {
    return Wishlist(
      id: json['id'] as String,
      ownerUserId: json['ownerUserId'] as String? ?? '',
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      year: json['year'] as int? ?? DateTime.now().year,
      coverImageUrl: json['coverImageUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      sharedUsers: (json['sharedUsers'] as List<dynamic>? ?? const [])
          .map((user) => _sharedUserFromJson(user as Map<String, dynamic>))
          .toList(growable: false),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => _itemFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _sharedUserToJson(SharedUser user) {
    return {
      'id': user.id,
      'name': user.name,
      'email': user.email,
      'role': user.role,
    };
  }

  SharedUser _sharedUserFromJson(Map<String, dynamic> json) {
    return SharedUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
    );
  }

  Map<String, Object?> _itemToJson(WishlistItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'rank': item.rank,
      'notes': item.notes,
      'priceLabel': item.priceLabel,
      'priority': item.priority,
      'status': item.status,
      'imageUrl': item.imageUrl,
      'productUrl': item.productUrl,
      'purchasedAt': item.purchasedAt?.toIso8601String(),
      'createdAt': item.createdAt.toIso8601String(),
    };
  }

  WishlistItem _itemFromJson(Map<String, dynamic> json) {
    return WishlistItem(
      id: json['id'] as String,
      title: json['title'] as String,
      rank: json['rank'] as int? ?? 1,
      notes: json['notes'] as String?,
      priceLabel: json['priceLabel'] as String?,
      priority: json['priority'] as String? ?? 'Medium',
      status: json['status'] as String? ?? 'Saved',
      imageUrl: json['imageUrl'] as String?,
      productUrl: json['productUrl'] as String?,
      purchasedAt: (json['purchasedAt'] as String?) == null
          ? null
          : DateTime.parse(json['purchasedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
