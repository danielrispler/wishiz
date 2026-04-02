import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class WishlistDto {
  const WishlistDto({
    required this.id,
    required this.ownerUserId,
    required this.title,
    required this.description,
    required this.year,
    required this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isArchived,
    required this.isShared,
    required this.sharedUsers,
    required this.items,
  });

  factory WishlistDto.fromJson(Map<String, dynamic> json) {
    return WishlistDto(
      id: json['id'] as String,
      ownerUserId: json['ownerUserId'] as String? ?? '',
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      year: json['year'] as int,
      coverImageUrl: json['coverImageUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      isShared: json['isShared'] as bool? ?? false,
      sharedUsers: (json['sharedUsers'] as List<dynamic>? ?? const [])
          .map((entry) => SharedUserDto.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((entry) =>
              WishlistItemDto.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

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
  final List<SharedUserDto> sharedUsers;
  final List<WishlistItemDto> items;

  Wishlist toEntity({
    String? fallbackOwnerUserId,
  }) {
    final sortedItems = [...items]
      ..sort((left, right) => left.rank.compareTo(right.rank));
    final resolvedOwnerUserId =
        ownerUserId.isEmpty ? (fallbackOwnerUserId ?? '') : ownerUserId;

    return Wishlist(
      id: id,
      ownerUserId: resolvedOwnerUserId,
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isArchived: isArchived,
      isShared: isShared,
      sharedUsers:
          sharedUsers.map((user) => user.toEntity()).toList(growable: false),
      items: sortedItems.map((item) => item.toEntity()).toList(growable: false),
    );
  }
}

class SharedUserDto {
  const SharedUserDto({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory SharedUserDto.fromJson(Map<String, dynamic> json) {
    return SharedUserDto(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
    );
  }

  final String id;
  final String name;
  final String email;
  final String role;

  SharedUser toEntity() {
    return SharedUser(
      id: id,
      name: name,
      email: email,
      role: role,
    );
  }
}

class WishlistItemDto {
  const WishlistItemDto({
    required this.id,
    required this.title,
    required this.rank,
    required this.notes,
    required this.priceLabel,
    required this.priority,
    required this.status,
    required this.imageUrl,
    required this.productUrl,
    required this.purchasedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WishlistItemDto.fromJson(Map<String, dynamic> json) {
    return WishlistItemDto(
      id: json['id'] as String,
      title: json['title'] as String,
      rank: json['rank'] as int,
      notes: json['notes'] as String?,
      priceLabel: json['priceLabel'] as String?,
      priority: json['priority'] as String? ?? WishlistItem.priorities[1],
      status: json['status'] as String? ?? WishlistItem.statuses.first,
      imageUrl: json['imageUrl'] as String?,
      productUrl: json['productUrl'] as String?,
      purchasedAt: json['purchasedAt'] == null
          ? null
          : DateTime.parse(json['purchasedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String title;
  final int rank;
  final String? notes;
  final String? priceLabel;
  final String priority;
  final String status;
  final String? imageUrl;
  final String? productUrl;
  final DateTime? purchasedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  WishlistItem toEntity() {
    return WishlistItem(
      id: id,
      title: title,
      rank: rank,
      notes: notes,
      priceLabel: priceLabel,
      priority: priority,
      status: status,
      imageUrl: imageUrl,
      productUrl: productUrl,
      purchasedAt: purchasedAt,
      createdAt: createdAt,
    );
  }
}
