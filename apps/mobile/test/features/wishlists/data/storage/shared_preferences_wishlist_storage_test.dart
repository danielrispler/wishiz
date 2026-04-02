import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  });
}
