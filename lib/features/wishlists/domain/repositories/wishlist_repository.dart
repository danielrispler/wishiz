import 'package:flutter/foundation.dart';
import 'package:wishiz/features/wishlists/domain/entities/shared_user.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

abstract class WishlistRepository {
  ValueListenable<List<Wishlist>> watchWishlists();

  List<Wishlist> getWishlists();

  Wishlist? findById(String id);

  Wishlist createWishlist({
    required String title,
    required String description,
    String? coverImageUrl,
    bool isShared = false,
  });

  Wishlist? updateWishlist({
    required String id,
    required String title,
    required String description,
    String? coverImageUrl,
    bool? isShared,
  });

  Wishlist? archiveWishlist(String id);

  Wishlist? restoreWishlist(String id);

  bool deleteWishlist(String id);

  Wishlist? addSharedUser({
    required String wishlistId,
    required String name,
    required String email,
    required String role,
  });

  bool removeSharedUser({
    required String wishlistId,
    required String userId,
  });

  WishlistItem addWishlistItem({
    required String wishlistId,
    required String title,
    String? notes,
    String? priceLabel,
    String priority = 'Medium',
    String status = 'Saved',
    String? imageUrl,
    String? productUrl,
  });

  WishlistItem? updateWishlistItem({
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

  bool deleteWishlistItem({
    required String wishlistId,
    required String itemId,
  });
}
