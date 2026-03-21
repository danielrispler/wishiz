import 'package:flutter_test/flutter_test.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/wishlist_storage.dart';

void main() {
  group('PersistentWishlistRepository', () {
    test('persists seeded data on first launch', () async {
      final storage = _FakeWishlistStorage();

      final repository = await PersistentWishlistRepository.create(
        storage: storage,
      );

      expect(repository.getWishlists(), isNotEmpty);
      expect(storage.value, isNotNull);
      expect(storage.value, contains('Home Decor'));
    });

    test('reloads saved wishlists and items from storage', () async {
      final storage = _FakeWishlistStorage();
      final repository = await PersistentWishlistRepository.create(
        storage: storage,
      );

      final wishlist = repository.createWishlist(
        title: 'Travel',
        description: 'Carry-on upgrades and essentials.',
        coverImageUrl: 'https://example.com/travel.jpg',
      );
      repository.addWishlistItem(
        wishlistId: wishlist.id,
        title: 'Weekender bag',
        imageUrl: 'https://example.com/bag.jpg',
        productUrl: 'https://example.com/bag',
      );
      await repository.flush();

      final reloadedRepository = await PersistentWishlistRepository.create(
        storage: storage,
      );
      final reloadedWishlist = reloadedRepository.findById(wishlist.id);

      expect(reloadedWishlist, isNotNull);
      expect(reloadedWishlist?.coverImageUrl, 'https://example.com/travel.jpg');
      expect(reloadedWishlist?.items, hasLength(1));
      expect(reloadedWishlist?.items.first.title, 'Weekender bag');
      expect(reloadedWishlist?.items.first.imageUrl, 'https://example.com/bag.jpg');
      expect(
        reloadedWishlist?.items.first.productUrl,
        'https://example.com/bag',
      );
    });

    test('reloads collaborators from storage', () async {
      final storage = _FakeWishlistStorage();
      final repository = await PersistentWishlistRepository.create(
        storage: storage,
      );

      final wishlist = repository.createWishlist(
        title: 'Dinner Party',
        description: 'Plates, flowers, and candles.',
      );
      repository.addSharedUser(
        wishlistId: wishlist.id,
        name: 'Maya',
        email: 'maya@example.com',
        role: 'Editor',
      );
      await repository.flush();

      final reloadedRepository = await PersistentWishlistRepository.create(
        storage: storage,
      );
      final reloadedWishlist = reloadedRepository.findById(wishlist.id);

      expect(reloadedWishlist?.isShared, isTrue);
      expect(reloadedWishlist?.sharedUsers, hasLength(1));
      expect(reloadedWishlist?.sharedUsers.first.name, 'Maya');
      expect(reloadedWishlist?.sharedUsers.first.role, 'Editor');
    });
  });
}

class _FakeWishlistStorage implements WishlistStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String nextValue) async {
    value = nextValue;
  }
}
