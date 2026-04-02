import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/navigation/wishiz_app_link.dart';

void main() {
  group('WishizAppLink', () {
    test('builds a stable wishlist deep link', () {
      expect(
        WishizAppLink.wishlistLink('wishlist-42'),
        'wishiz://lists/wishlist-42',
      );
    });

    test('extracts a wishlist id from a direct deep link', () {
      expect(
        WishizAppLink.extractWishlistId('wishiz://lists/wishlist-42'),
        'wishlist-42',
      );
    });

    test('extracts a wishlist id from share text that embeds the link', () {
      expect(
        WishizAppLink.extractWishlistId(
          'Open this Wishiz list in the app:\n'
          'wishiz://lists/wishlist-42\n\n'
          'Join my Wishiz list "Hosting" for 2026.',
        ),
        'wishlist-42',
      );
    });

    test('ignores trailing punctuation around embedded links', () {
      expect(
        WishizAppLink.extractWishlistId(
          'Join here: wishiz://lists/wishlist-42.',
        ),
        'wishlist-42',
      );
    });
  });
}
