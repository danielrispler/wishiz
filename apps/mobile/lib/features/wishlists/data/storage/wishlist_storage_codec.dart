import 'dart:convert';

import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_invite.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_member.dart';

class WishlistStorageCodec {
  const WishlistStorageCodec();

  String encode(List<Wishlist> wishlists) {
    return jsonEncode(wishlists.map(_wishlistToJson).toList(growable: false));
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
      'ownerFullName': wishlist.ownerFullName,
      'title': wishlist.title,
      'description': wishlist.description,
      'year': wishlist.year,
      'coverImageUrl': wishlist.coverImageUrl,
      'createdAt': wishlist.createdAt.toIso8601String(),
      'updatedAt': wishlist.updatedAt.toIso8601String(),
      'isArchived': wishlist.isArchived,
      'members': wishlist.members.map(_memberToJson).toList(growable: false),
      'invites': wishlist.invites.map(_inviteToJson).toList(growable: false),
      'items': wishlist.items.map(_itemToJson).toList(growable: false),
    };
  }

  Wishlist _wishlistFromJson(Map<String, dynamic> json) {
    return Wishlist(
      id: json['id'] as String,
      ownerUserId: _requiredNonEmptyString(json, 'ownerUserId'),
      ownerFullName: json['ownerFullName'] as String? ?? 'List Owner',
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      year: json['year'] as int? ?? DateTime.now().year,
      coverImageUrl: json['coverImageUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isArchived: json['isArchived'] as bool? ?? false,
      members: (json['members'] as List<dynamic>? ?? const [])
          .map((member) => _memberFromJson(member as Map<String, dynamic>))
          .toList(growable: false),
      invites: (json['invites'] as List<dynamic>? ?? const [])
          .map((invite) => _inviteFromJson(invite as Map<String, dynamic>))
          .toList(growable: false),
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => _itemFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _memberToJson(WishlistMember member) {
    return {
      'userId': member.userId,
      'email': member.email,
      'fullName': member.fullName,
      'role': member.role.apiValue,
      'createdAt': member.createdAt.toIso8601String(),
      'updatedAt': member.updatedAt.toIso8601String(),
    };
  }

  WishlistMember _memberFromJson(Map<String, dynamic> json) {
    return WishlistMember(
      userId: json['userId'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      role: WishlistMemberRole.fromApiValue(json['role'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, Object?> _inviteToJson(WishlistInvite invite) {
    return {
      'id': invite.id,
      'email': invite.email,
      'role': invite.role.apiValue,
      'invitedByUserId': invite.invitedByUserId,
      'acceptedAt': invite.acceptedAt?.toIso8601String(),
      'expiresAt': invite.expiresAt.toIso8601String(),
      'createdAt': invite.createdAt.toIso8601String(),
      'updatedAt': invite.updatedAt.toIso8601String(),
      'token': invite.token,
    };
  }

  WishlistInvite _inviteFromJson(Map<String, dynamic> json) {
    return WishlistInvite(
      id: json['id'] as String,
      email: json['email'] as String?,
      role: WishlistMemberRole.fromApiValue(json['role'] as String),
      invitedByUserId: json['invitedByUserId'] as String?,
      acceptedAt: (json['acceptedAt'] as String?) == null
          ? null
          : DateTime.parse(json['acceptedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      token: json['token'] as String?,
    );
  }

  Map<String, Object?> _itemToJson(WishlistItem item) {
    return {
      'id': item.id,
      'title': item.title,
      'rank': item.rank,
      'notes': item.notes,
      'priceLabel': item.priceLabel,
      'priority': item.priority.apiValue,
      'status': item.status.apiValue,
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
      priority: WishlistItemPriority.fromApiValue(
        json['priority'] as String? ?? WishlistItemPriority.medium.apiValue,
      ),
      status: WishlistItemStatus.fromApiValue(
        json['status'] as String? ?? WishlistItemStatus.saved.apiValue,
      ),
      imageUrl: json['imageUrl'] as String?,
      productUrl: json['productUrl'] as String?,
      purchasedAt: (json['purchasedAt'] as String?) == null
          ? null
          : DateTime.parse(json['purchasedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  String _requiredNonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key] as String?;
    if (value == null || value.trim().isEmpty) {
      throw FormatException('$key is required.');
    }
    return value;
  }
}
