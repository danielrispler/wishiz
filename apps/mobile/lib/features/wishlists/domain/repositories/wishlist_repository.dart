import 'package:flutter/foundation.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

abstract class WishlistRepository {
  ValueListenable<List<Wishlist>> watchWishlists();

  List<Wishlist> getWishlists();

  Wishlist? findById(String id);

  Future<Wishlist> createWishlist({
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    bool isShared = false,
  });

  Future<Wishlist?> updateWishlist({
    required String id,
    required String title,
    required String description,
    required int year,
    String? coverImageUrl,
    bool? isShared,
  });

  Future<Wishlist?> archiveWishlist(String id);

  Future<Wishlist?> restoreWishlist(String id);

  Future<bool> deleteWishlist(String id);

  Future<Wishlist?> addSharedUser({
    required String wishlistId,
    required String name,
    required String email,
    required String role,
  });

  Future<bool> removeSharedUser({
    required String wishlistId,
    required String userId,
  });

  Future<WishlistItem> addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    String priority = 'Medium',
    String status = 'Saved',
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
    required String status,
  });

  Future<WishlistItem?> updateWishlistItem({
    required String wishlistId,
    required String itemId,
    required String title,
    String? notes,
    String? priceLabel,
    String priority = 'Medium',
    String status = 'Saved',
    String? imageUrl,
    String? productUrl,
  });

  Future<bool> deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  });
}
