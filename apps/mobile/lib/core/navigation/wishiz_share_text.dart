import 'package:wishiz/core/navigation/wishiz_app_link.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class WishizShareText {
  WishizShareText._();

  static String buildWishlistShareText({required Wishlist wishlist}) {
    final lines = <String>[
      'Open this Wishiz list.',
      WishizAppLink.wishlistShareLink(wishlist.id),
    ];

    return lines.join('\n');
  }

  static String buildWishlistItemShareText({
    required Wishlist wishlist,
    required WishlistItem item,
  }) {
    final lines = <String>[
      'Take a look at this item in my Wishiz list.',
      WishizAppLink.wishlistShareLink(wishlist.id),
    ];

    return lines.join('\n');
  }
}
