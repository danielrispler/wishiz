import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/core/navigation/wishiz_share_text.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

void main() {
  group('WishizShareText', () {
    test('builds wishlist share text with an https link on the first line', () {
      final wishlist = _buildWishlist();

      final text = WishizShareText.buildWishlistShareText(wishlist: wishlist);

      expect(text.split('\n').first, 'https://wishiz.app/lists/wishlist-42');
      expect(text, isNot(contains('wishiz://lists/')));
    });

    test('builds item share text with an https link on the first line', () {
      final wishlist = _buildWishlist();
      final item = WishlistItem(
        id: 'item-1',
        title: 'Espresso Cups',
        rank: 1,
        createdAt: DateTime(2026, 1, 1),
      );

      final text = WishizShareText.buildWishlistItemShareText(
        wishlist: wishlist,
        item: item,
        extraLines: const ['https://example.com/products/cups'],
      );

      final lines = text.split('\n');
      expect(lines.first, 'https://wishiz.app/lists/wishlist-42');
      expect(text, contains('https://example.com/products/cups'));
      expect(text, isNot(contains('wishiz://lists/')));
    });
  });
}

Wishlist _buildWishlist() {
  return Wishlist(
    id: 'wishlist-42',
    ownerUserId: 'user-1',
    title: 'Hosting',
    description: 'Table setting ideas',
    year: 2026,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}
