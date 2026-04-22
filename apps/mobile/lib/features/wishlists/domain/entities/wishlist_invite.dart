import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';

class WishlistInvite {
  const WishlistInvite({
    required this.id,
    required this.email,
    required this.role,
    this.invitedByUserId,
    this.acceptedAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.token,
  });

  final String id;
  final String email;
  final WishlistMemberRole role;
  final String? invitedByUserId;
  final DateTime? acceptedAt;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? token;

  WishlistInvite copyWith({
    String? id,
    String? email,
    WishlistMemberRole? role,
    Object? invitedByUserId = _noValue,
    Object? acceptedAt = _noValue,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? token = _noValue,
  }) {
    return WishlistInvite(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      invitedByUserId: identical(invitedByUserId, _noValue)
          ? this.invitedByUserId
          : invitedByUserId as String?,
      acceptedAt: identical(acceptedAt, _noValue)
          ? this.acceptedAt
          : acceptedAt as DateTime?,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      token: identical(token, _noValue) ? this.token : token as String?,
    );
  }
}

const Object _noValue = Object();
