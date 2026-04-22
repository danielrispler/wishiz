import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/in_memory_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/domain/entities/wishlist_enums.dart';

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
        status: WishlistItemStatus.purchased,
      );

      final refreshedWishlist = repository.findById(wishlist.id);

      expect(firstItem.rank, 1);
      expect(secondItem.rank, 2);
      expect(refreshedWishlist?.activeItemCount, 1);
      expect(refreshedWishlist?.purchasedItemCount, 1);
      expect(
        refreshedWishlist?.purchasedItems.first.status,
        WishlistItemStatus.purchased,
      );
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
        status: WishlistItemStatus.purchased,
      );

      final originalPurchasedAt = item.purchasedAt;
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final updatedItem = await repository.updateWishlistItem(
        wishlistId: wishlist.id,
        itemId: item.id,
        title: 'Stoneware bowl set, matte glaze',
        status: WishlistItemStatus.purchased,
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
        status: WishlistItemStatus.purchased,
      );

      final originalPurchasedAt = item.purchasedAt;
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final updatedItem = await repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: item.id,
        status: WishlistItemStatus.purchased,
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
        status: WishlistItemStatus.purchased,
      );

      final restoredItem = await repository.updateWishlistItemStatus(
        wishlistId: wishlist.id,
        itemId: item.id,
        status: WishlistItemStatus.saved,
      );

      final refreshedWishlist = repository.findById(wishlist.id);
      expect(restoredItem?.status, WishlistItemStatus.saved);
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

    test('creates and deletes invites on a wishlist', () async {
      final repository = InMemoryWishlistRepository(
        ownerUserId: ownerUserId,
        initialWishlists: [],
      );
      final wishlist = await repository.createWishlist(
        title: 'Weekend Trip',
        description: 'Packing, bookings, and gift ideas.',
        year: 2026,
      );

      final invite = await repository.createInvite(
        wishlistId: wishlist.id,
        email: 'maya@example.com',
        role: WishlistMemberRole.editor,
      );

      final refreshedWishlist = repository.findById(wishlist.id);
      final removed = await repository.deleteInvite(
        wishlistId: wishlist.id,
        inviteId: invite.id,
      );

      expect(refreshedWishlist?.ownerUserId, ownerUserId);
      expect(refreshedWishlist?.invites, hasLength(1));
      expect(refreshedWishlist?.invites.first.email, 'maya@example.com');
      expect(refreshedWishlist?.invites.first.role, WishlistMemberRole.editor);
      expect(removed, isTrue);
      expect(repository.findById(wishlist.id)?.invites, isEmpty);
    });
  });
}
