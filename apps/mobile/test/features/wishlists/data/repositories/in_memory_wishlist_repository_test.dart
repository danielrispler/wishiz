import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';

void main() {
  final uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  group('InMemoryWishlistRepository', () {
    test('creates a wishlist with a year and exposes it through the notifier',
        () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);

      final createdWishlist = repository.createWishlist(
        title: 'Reading Corner',
        description: 'Warm textures and quieter lighting.',
        year: 2027,
        coverImageUrl: 'https://example.com/cover.jpg',
        isShared: true,
      );

      expect(repository.getWishlists(), hasLength(1));
      expect(createdWishlist.id, matches(uuidPattern));
      expect(repository.getWishlists().first.title, 'Reading Corner');
      expect(repository.getWishlists().first.year, 2027);
      expect(repository.watchWishlists().value.first.id, createdWishlist.id);
      expect(
        repository.watchWishlists().value.first.coverImageUrl,
        'https://example.com/cover.jpg',
      );
      expect(repository.watchWishlists().value.first.isShared, isTrue);
    });

    test('adds items with rank order and updates purchase status', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);
      final wishlist = repository.createWishlist(
        title: 'Hosting',
        description: 'Ceramics and table details.',
        year: 2026,
      );

      final firstItem = repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Stoneware bowl set',
      );
      final secondItem = repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Large serving spoon',
      );

      repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: secondItem.id,
        status: 'Purchased',
      );

      final refreshedWishlist = repository.findById(wishlist.id);

      expect(firstItem.rank, 1);
      expect(secondItem.rank, 2);
      expect(refreshedWishlist?.activeItemCount, 1);
      expect(refreshedWishlist?.purchasedItemCount, 1);
      expect(refreshedWishlist?.purchasedItems.first.status, 'Purchased');
      expect(refreshedWishlist?.purchasedItems.first.purchasedAt, isNotNull);
    });

    test('reprioritizes items by assigning sequential rank values', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);
      final wishlist = repository.createWishlist(
        title: 'Desk Setup',
        description: 'Work tools and upgrades.',
        year: 2026,
      );
      final first = repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Desk lamp',
      );
      final second = repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Monitor stand',
      );

      repository.reorderWishlistItems(
        wishlistId: wishlist.id,
        orderedItemIds: [second.id, first.id],
      );

      final refreshedWishlist = repository.findById(wishlist.id);

      expect(refreshedWishlist?.items.first.id, second.id);
      expect(refreshedWishlist?.items.first.rank, 1);
      expect(refreshedWishlist?.items.last.rank, 2);
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

    test('adds and removes collaborators on a shared wishlist', () {
      final repository = InMemoryWishlistRepository(initialWishlists: []);
      final wishlist = repository.createWishlist(
        title: 'Weekend Trip',
        description: 'Packing, bookings, and gift ideas.',
        year: 2026,
      );

      final sharedWishlist = repository.addSharedUser(
        wishlistId: wishlist.id,
        name: 'Maya',
        email: 'maya@example.com',
        role: 'Editor',
      );

      final collaboratorId = sharedWishlist!.sharedUsers.first.id;
      final removed = repository.removeSharedUser(
        wishlistId: wishlist.id,
        userId: collaboratorId,
      );

      expect(sharedWishlist.isShared, isTrue);
      expect(sharedWishlist.sharedUsers, hasLength(1));
      expect(sharedWishlist.sharedUsers.first.email, 'maya@example.com');
      expect(removed, isTrue);
      expect(repository.findById(wishlist.id)?.sharedUsers, isEmpty);
      expect(repository.findById(wishlist.id)?.isShared, isFalse);
    });
  });
}
