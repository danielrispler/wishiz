import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';

void main() {
  final uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  group('InMemoryWishlistRepository', () {
    test('creates a wishlist with a UUID and exposes it through the notifier', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);

      final createdWishlist = repository.createWishlist(
        title: 'Reading Corner',
        description: 'Warm textures and quieter lighting.',
        coverImageUrl: 'https://example.com/cover.jpg',
        isShared: true,
      );

      expect(repository.getWishlists(), hasLength(1));
      expect(createdWishlist.id, matches(uuidPattern));
      expect(repository.getWishlists().first.title, 'Reading Corner');
      expect(repository.watchWishlists().value.first.id, createdWishlist.id);
      expect(repository.watchWishlists().value.first.coverImageUrl, 'https://example.com/cover.jpg');
      expect(repository.watchWishlists().value.first.isShared, isTrue);
    });

    test('archives and restores an existing wishlist', () {
      final repository = InMemoryWishlistRepository();
      final wishlist = repository.getWishlists().first;

      final archived = repository.archiveWishlist(wishlist.id);
      final restored = repository.restoreWishlist(wishlist.id);

      expect(archived?.isArchived, isTrue);
      expect(restored?.isArchived, isFalse);
    });

    test('deletes a wishlist by id', () {
      final repository = InMemoryWishlistRepository();
      final initialCount = repository.getWishlists().length;
      final wishlist = repository.getWishlists().first;

      final wasDeleted = repository.deleteWishlist(wishlist.id);

      expect(wasDeleted, isTrue);
      expect(repository.getWishlists(), hasLength(initialCount - 1));
      expect(repository.findById(wishlist.id), isNull);
    });

    test('adds and updates an item inside a wishlist', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);
      final wishlist = repository.createWishlist(
        title: 'Hosting',
        description: 'Ceramics and table details.',
      );

      final item = repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Stoneware bowl set',
        notes: 'Look for a matte finish.',
        priceLabel: '\$84',
        imageUrl: 'https://example.com/bowls.jpg',
        productUrl: 'https://example.com/bowls',
      );

      final updatedItem = repository.updateWishlistItem(
        wishlistId: wishlist.id,
        itemId: item.id,
        title: 'Stoneware serving bowl set',
        notes: null,
        priceLabel: null,
        imageUrl: null,
        productUrl: 'https://example.com/serving-bowls',
      );

      final refreshedWishlist = repository.findById(wishlist.id);

      expect(updatedItem, isNotNull);
      expect(item.id, matches(uuidPattern));
      expect(refreshedWishlist?.items, hasLength(1));
      expect(refreshedWishlist?.items.first.title, 'Stoneware serving bowl set');
      expect(refreshedWishlist?.items.first.notes, isNull);
      expect(refreshedWishlist?.items.first.priceLabel, isNull);
      expect(refreshedWishlist?.items.first.imageUrl, isNull);
      expect(
        refreshedWishlist?.items.first.productUrl,
        'https://example.com/serving-bowls',
      );
    });

    test('deletes an item from a wishlist', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);
      final wishlist = repository.createWishlist(
        title: 'Desk Setup',
        description: 'Work tools and upgrades.',
      );
      final item = repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Desk lamp',
      );

      final wasDeleted = repository.deleteWishlistItem(
        wishlistId: wishlist.id,
        itemId: item.id,
      );

      expect(wasDeleted, isTrue);
      expect(repository.findById(wishlist.id)?.items, isEmpty);
    });

    test('throws when adding an item to a missing wishlist', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);

      expect(
        () => repository.addWishlistItem(
          wishlistId: 'missing-wishlist',
          title: 'Desk lamp',
        ),
        throwsStateError,
      );
    });
  });
}
