import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/navigation/wishiz_app_link.dart';

void main() {
  group('WishizAppLink', () {
    test('builds a stable custom-scheme wishlist deep link', () {
      expect(
        WishizAppLink.wishlistLink('wishlist-42'),
        'wishiz://lists/wishlist-42',
      );
    });

    test('builds a stable https wishlist share link', () {
      expect(
        WishizAppLink.wishlistShareLink('wishlist-42'),
        'https://wishiz.app/lists/wishlist-42',
      );
    });

    test('extracts a wishlist id from a direct deep link', () {
      expect(
        WishizAppLink.extractWishlistId('wishiz://lists/wishlist-42'),
        'wishlist-42',
      );
    });

    test('extracts a wishlist id from a direct https share link', () {
      expect(
        WishizAppLink.extractWishlistId('https://wishiz.app/lists/wishlist-42'),
        'wishlist-42',
      );
    });

    test('extracts a wishlist id from share text that embeds the link', () {
      expect(
        WishizAppLink.extractWishlistId(
          'https://wishiz.app/lists/wishlist-42\n\n'
          'Open this Wishiz list in the app.\n'
          'Join my Wishiz list "Hosting" for 2026.',
        ),
        'wishlist-42',
      );
    });

    test('ignores trailing punctuation around embedded links', () {
      expect(
        WishizAppLink.extractWishlistId(
          'Join here: https://wishiz.app/lists/wishlist-42.',
        ),
        'wishlist-42',
      );
    });
  });
}
