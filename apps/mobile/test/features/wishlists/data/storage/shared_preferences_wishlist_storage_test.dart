import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishiz/features/wishlists/data/repositories/persistent_wishlist_repository.dart';
import 'package:wishiz/features/wishlists/data/storage/shared_preferences_wishlist_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesWishlistStorage', () {
    test('stores wishlists per user key', () async {
      SharedPreferences.setMockInitialValues({});

      final firstUserStorage = await SharedPreferencesWishlistStorage.create(
        userId: 'user-1',
      );
      final secondUserStorage = await SharedPreferencesWishlistStorage.create(
        userId: 'user-2',
      );

      await firstUserStorage.write('first-user-lists');
      await secondUserStorage.write('second-user-lists');

      expect(await firstUserStorage.read(), 'first-user-lists');
      expect(await secondUserStorage.read(), 'second-user-lists');
    });

    test('clears the legacy shared key during initialization', () async {
      SharedPreferences.setMockInitialValues({
        'wishiz.wishlists': 'legacy-shared-lists',
      });

      final storage = await SharedPreferencesWishlistStorage.create(
        userId: 'user-1',
      );
      final preferences = await SharedPreferences.getInstance();

      expect(await storage.read(), isNull);
      expect(preferences.getString('wishiz.wishlists'), isNull);
    });

    test('wishlists created by one user stay hidden from another user', () async {
      SharedPreferences.setMockInitialValues({});

      final firstUserStorage = await SharedPreferencesWishlistStorage.create(
        userId: 'user-1',
      );
      final secondUserStorage = await SharedPreferencesWishlistStorage.create(
        userId: 'user-2',
      );

      final firstUserRepository = await PersistentWishlistRepository.create(
        storage: firstUserStorage,
        ownerUserId: 'user-1',
      );
      final secondUserRepository = await PersistentWishlistRepository.create(
        storage: secondUserStorage,
        ownerUserId: 'user-2',
      );

      final createdWishlist = await firstUserRepository.createWishlist(
        title: 'Private List',
        description: 'Only user one should see this.',
        year: 2026,
      );

      expect(createdWishlist.ownerUserId, 'user-1');
      expect(
        firstUserRepository
            .getWishlists()
            .any((wishlist) => wishlist.id == createdWishlist.id),
        isTrue,
      );
      expect(
        secondUserRepository
            .getWishlists()
            .any((wishlist) => wishlist.id == createdWishlist.id),
        isFalse,
      );
    });
  });
}
