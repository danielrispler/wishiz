import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';

class WishlistMember {
  const WishlistMember({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String email;
  final String fullName;
  final WishlistMemberRole role;
  final DateTime createdAt;
  final DateTime updatedAt;

  WishlistMember copyWith({
    String? userId,
    String? email,
    String? fullName,
    WishlistMemberRole? role,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WishlistMember(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
