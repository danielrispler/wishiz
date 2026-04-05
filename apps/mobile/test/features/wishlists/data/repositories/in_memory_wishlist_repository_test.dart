import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';

void main() {
  const ownerUserId = 'user-dana';
  final uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  group('InMemoryWishlistRepository', () {
    test('starts empty when no initial wishlists are provided', () {
      final repository = InMemoryWishlistRepository(ownerUserId: ownerUserId);

      expect(repository.getWishlists(), isEmpty);
      expect(repository.watchWishlists().value, isEmpty);
    });

    test(
      'creates a wishlist with a year and exposes it through the notifier',
      () async {
        final repository = InMemoryWishlistRepository(
          ownerUserId: ownerUserId,
          initialWishlists: [],
        );

        final createdWishlist = await repository.createWishlist(
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
        expect(
          repository.watchWishlists().value.first.ownerUserId,
          ownerUserId,
        );
      },
    );

    test('adds items with rank order and updates purchase status', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Hosting',
        description: 'Ceramics and table details.',
        year: 2026,
      );

      final firstItem = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Stoneware bowl set',
      );
      final secondItem = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Large serving spoon',
      );

      await repository.updateWishlistItemStatus(
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

    test('preserves purchasedAt when a purchased item is edited', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Hosting',
        description: 'Ceramics and table details.',
        year: 2026,
      );

      final item = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Stoneware bowl set',
        status: 'Purchased',
      );

      final originalPurchasedAt = item.purchasedAt;
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final updatedItem = await repository.updateWishlistItem(
        wishlistId: wishlist.id,
        itemId: item.id,
        title: 'Stoneware bowl set, matte glaze',
        status: 'Purchased',
      );

      expect(updatedItem?.purchasedAt, isNotNull);
      expect(updatedItem?.purchasedAt, originalPurchasedAt);
    });

    test('preserves purchasedAt when purchased status is set again', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Hosting',
        description: 'Ceramics and table details.',
        year: 2026,
      );

      final item = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Stoneware bowl set',
        status: 'Purchased',
      );

      final originalPurchasedAt = item.purchasedAt;
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final updatedItem = await repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: item.id,
        status: 'Purchased',
      );

      expect(updatedItem?.purchasedAt, isNotNull);
      expect(updatedItem?.purchasedAt, originalPurchasedAt);
    });

    test('moves a purchased item back to active items when restored', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Hosting',
        description: 'Ceramics and table details.',
        year: 2026,
      );

      final item = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Stoneware bowl set',
        status: 'Purchased',
      );

      final restoredItem = await repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: item.id,
        status: 'Saved',
      );

      final refreshedWishlist = repository.findById(wishlist.id);
      expect(restoredItem?.status, 'Saved');
      expect(restoredItem?.purchasedAt, isNull);
      expect(refreshedWishlist?.purchasedItems, isEmpty);
      expect(refreshedWishlist?.activeItems.map((entry) => entry.id), [
        item.id,
      ]);
    });

    test('reprioritizes items by assigning sequential rank values', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Desk Setup',
        description: 'Work tools and upgrades.',
        year: 2026,
      );
      final first = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Desk lamp',
      );
      final second = await repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Monitor stand',
      );

      await repository.reorderWishlistItems(
        wishlistId: wishlist.id,
        orderedItemIds: [second.id, first.id],
      );

      final refreshedWishlist = repository.findById(wishlist.id);

      expect(refreshedWishlist?.items.first.id, second.id);
      expect(refreshedWishlist?.items.first.rank, 1);
      expect(refreshedWishlist?.items.last.rank, 2);
    });

    test('throws when adding an item to a missing wishlist', () {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );

      expect(
        repository.addWishlistItem(
          wishlistId: 'missing-wishlist',
          title: 'Desk lamp',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('adds and removes collaborators on a shared wishlist', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Weekend Trip',
        description: 'Packing, bookings, and gift ideas.',
        year: 2026,
      );

      final sharedWishlist = await repository.addSharedUser(
        wishlistId: wishlist.id,
        name: 'Maya',
        email: 'maya@example.com',
        role: 'Editor',
      );

      final collaboratorId = sharedWishlist!.sharedUsers.first.id;
      final removed = await repository.removeSharedUser(
        wishlistId: wishlist.id,
        userId: collaboratorId,
      );

      expect(sharedWishlist.isShared, isTrue);
      expect(sharedWishlist.ownerUserId, ownerUserId);
      expect(sharedWishlist.sharedUsers, hasLength(1));
      expect(sharedWishlist.sharedUsers.first.email, 'maya@example.com');
      expect(removed, isTrue);
      expect(repository.findById(wishlist.id)?.sharedUsers, isEmpty);
      expect(repository.findById(wishlist.id)?.isShared, isFalse);
    });
  });
}
