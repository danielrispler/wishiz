import 'package:flutter/foundation.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_invite.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

abstract class WishlistRepository {
  Future<void> refresh();

  Future<String> uploadImage({
    required List<int> bytes,
    required String fileName,
    String? contentType,
  });

  ValueListenable<List<Wishlist>> watchWishlists();

  List<Wishlist> getWishlists();

  Wishlist? findById(String id);

  Future<Wishlist?> joinWishlist({required String id, required String token});

  Future<Wishlist> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
  });

  Future<Wishlist?> updateWishlist({
    required String id,
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
  });

  Future<Wishlist?> archiveWishlist(String id);

  Future<Wishlist?> restoreWishlist(String id);

  Future<bool> deleteWishlist(String id);

  Future<WishlistInvite> createInvite({
    required String wishlistId,
    String? email,
    required WishlistMemberRole role,
  });

  Future<bool> deleteInvite({
    required String wishlistId,
    required String inviteId,
  });

  Future<bool> removeMember({
    required String wishlistId,
    required String userId,
  });

  Future<void> updateMemberRole({
    required String wishlistId,
    required String userId,
    required WishlistMemberRole role,
  });

  Future<WishlistItem> addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    WishlistItemPriority priority = WishlistItemPriority.medium,
    WishlistItemStatus status = WishlistItemStatus.saved,
    String? imageUrl,
    String? productUrl,
  });

  Future<Wishlist?> reorderWishlistItems({
    required String wishlistId,
    required List<String> orderedItemIds,
  });

  Future<WishlistItem?> updateWishlistItemStatus({
    required String wishlistId,
    required String itemId,
    required WishlistItemStatus status,
  });

  Future<WishlistItem?> updateWishlistItem({
    required String wishlistId,
    required String itemId,
    required String title,
    String? notes,
    String? priceLabel,
    WishlistItemPriority priority = WishlistItemPriority.medium,
    WishlistItemStatus status = WishlistItemStatus.saved,
    String? imageUrl,
    String? productUrl,
  });

  Future<bool> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  });
}
