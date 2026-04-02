import 'package:wishiz/core/navigation/wishiz_app_link.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

class WishizShareText {
  WishizShareText._();

  static String buildWishlistShareText({
    required Wishlist wishlist,
    List<String> previewLines = const [],
  }) {
    final lines = <String>[
      WishizAppLink.wishlistShareLink(wishlist.id),
      '',
      'Open this Wishiz list in the app.',
      'Join my Wishiz list "${wishlist.title}" for ${wishlist.year}.',
      ...previewLines,
    ];

    return lines.join('\n');
  }

  static String buildWishlistItemShareText({
    required Wishlist wishlist,
    required WishlistItem item,
    List<String> extraLines = const [],
  }) {
    final lines = <String>[
      WishizAppLink.wishlistShareLink(wishlist.id),
      '',
      '${item.title} from ${wishlist.title}',
      'Rank: #${item.rank}',
      'Open this list in Wishiz.',
      ...extraLines,
    ];

    return lines.join('\n');
  }
}
