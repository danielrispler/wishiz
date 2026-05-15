import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_invite.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';

class WishlistDto {
  const WishlistDto({
    required this.id,
    required this.ownerUserId,
    required this.ownerFullName,
    required this.title,
    required this.description,
    required this.year,
    required this.coverImageUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isArchived,
    required this.members,
    required this.invites,
    required this.items,
  });

  factory WishlistDto.fromJson(Map<String, dynamic> json) {
    final ownerUserId = json['ownerUserId'] as String?;
    if (ownerUserId == null || ownerUserId.trim().isEmpty) {
      throw const FormatException('Wishlist ownerUserId is required.');
    }

    return WishlistDto(
      id: json['id'] as String,
      ownerUserId: ownerUserId,
      ownerFullName: json['ownerFullName'] as String? ?? 'List Owner',
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      year: json['year'] as int,
      coverImageUrl: json['coverImageUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      members: (json['members'] as List<dynamic>? ?? const [])
          .map(
            (entry) =>
                WishlistMemberDto.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      invites: (json['invites'] as List<dynamic>? ?? const [])
          .map(
            (entry) =>
                WishlistInviteDto.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (entry) => WishlistItemDto.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final String id;
  final String ownerUserId;
  final String ownerFullName;
  final String title;
  final String description;
  final int year;
  final String? coverImageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isArchived;
  final List<WishlistMemberDto> members;
  final List<WishlistInviteDto> invites;
  final List<WishlistItemDto> items;

  Wishlist toEntity() {
    final sortedItems = [...items]
      ..sort((left, right) => left.rank.compareTo(right.rank));

    return Wishlist(
      id: id,
      ownerUserId: ownerUserId,
      ownerFullName: ownerFullName,
      title: title,
      description: description,
      year: year,
      coverImageUrl: coverImageUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isArchived: isArchived,
      members: members
          .map((member) => member.toEntity())
          .toList(growable: false),
      invites: invites
          .map((invite) => invite.toEntity())
          .toList(growable: false),
      items: sortedItems.map((item) => item.toEntity()).toList(growable: false),
    );
  }
}

class WishlistMemberDto {
  const WishlistMemberDto({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WishlistMemberDto.fromJson(Map<String, dynamic> json) {
    return WishlistMemberDto(
      userId: json['userId'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String? ?? '',
      role: WishlistMemberRole.fromApiValue(json['role'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String userId;
  final String email;
  final String fullName;
  final WishlistMemberRole role;
  final DateTime createdAt;
  final DateTime updatedAt;

  WishlistMember toEntity() {
    return WishlistMember(
      userId: userId,
      email: email,
      fullName: fullName,
      role: role,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class WishlistInviteDto {
  const WishlistInviteDto({
    required this.id,
    required this.email,
    required this.role,
    required this.invitedByUserId,
    required this.acceptedAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    required this.token,
  });

  factory WishlistInviteDto.fromJson(Map<String, dynamic> json) {
    return WishlistInviteDto(
      id: json['id'] as String,
      email: json['email'] as String,
      role: WishlistMemberRole.fromApiValue(json['role'] as String),
      invitedByUserId: json['invitedByUserId'] as String?,
      acceptedAt: json['acceptedAt'] == null
          ? null
          : DateTime.parse(json['acceptedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      token: json['token'] as String?,
    );
  }

  final String id;
  final String email;
  final WishlistMemberRole role;
  final String? invitedByUserId;
  final DateTime? acceptedAt;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? token;

  WishlistInvite toEntity() {
    return WishlistInvite(
      id: id,
      email: email,
      role: role,
      invitedByUserId: invitedByUserId,
      acceptedAt: acceptedAt,
      expiresAt: expiresAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      token: token,
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
      priority: WishlistItemPriority.fromApiValue(
        json['priority'] as String? ?? WishlistItemPriority.medium.apiValue,
      ),
      status: WishlistItemStatus.fromApiValue(
        json['status'] as String? ?? WishlistItemStatus.saved.apiValue,
      ),
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
  final WishlistItemPriority priority;
  final WishlistItemStatus status;
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
