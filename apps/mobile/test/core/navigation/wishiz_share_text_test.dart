import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/wishlist_share_text.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_item.dart';

void main() {
  group('WishizShareText', () {
    test('builds wishlist share text with an https link on the first line', () {
      final wishlist = _buildWishlist();

      final text = WishizShareText.buildWishlistShareText(wishlist: wishlist);
      final lines = text.split('\n');

      expect(lines, [
        'Open this Wishiz list.',
        'https://wishiz.app/lists/wishlist-42',
      ]);
      expect(text, isNot(contains('Hosting')));
      expect(text, isNot(contains('2026')));
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
      );

      final lines = text.split('\n');
      expect(lines, [
        'Take a look at this item in my Wishiz list.',
        'https://wishiz.app/lists/wishlist-42',
      ]);
      expect(text, isNot(contains('Espresso Cups')));
      expect(text, isNot(contains('Hosting')));
      expect(text, isNot(contains('Rank:')));
      expect(text, isNot(contains('wishiz://lists/')));
    });

    test('builds invite share text with a tokenized https link', () {
      final wishlist = _buildWishlist();

      final text = WishizShareText.buildWishlistInviteShareText(
        wishlist: wishlist,
        inviteToken: 'invite-token',
      );

      expect(text.split('\n'), [
        'Join my Wishiz list.',
        'https://wishiz.app/lists/wishlist-42?token=invite-token',
      ]);
    });
  });
}

Wishlist _buildWishlist() {
  return Wishlist(
    id: 'wishlist-42',
    ownerUserId: 'user-1',
    ownerFullName: 'Maya Chen',
    title: 'Hosting',
    description: 'Table setting ideas',
    year: 2026,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}
