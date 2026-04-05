import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishiz/features/wishlists/data/storage/wishlist_storage.dart';

class SharedPreferencesWishlistStorage implements WishlistStorage {
  SharedPreferencesWishlistStorage._({
    required SharedPreferences preferences,
    required String storageKey,
  }) : _preferences = preferences,
       _storageKey = storageKey;

  static const String _storageKeyPrefix = 'wishiz.wishlists.';
  static const String _legacyStorageKey = 'wishiz.wishlists';

  final SharedPreferences _preferences;
  final String _storageKey;

  static Future<void> clearLegacyData() async {
    final preferences = await SharedPreferences.getInstance();
    final keysToRemove = preferences
        .getKeys()
        .where((key) {
          return key == _legacyStorageKey || key.startsWith(_storageKeyPrefix);
        })
        .toList(growable: false);

    for (final key in keysToRemove) {
      await preferences.remove(key);
    }
  }

  static Future<SharedPreferencesWishlistStorage> create({
    required String userId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyStorageKey);
    return SharedPreferencesWishlistStorage._(
      preferences: preferences,
      storageKey: '$_storageKeyPrefix$userId',
    );
  }

  @override
  Future<String?> read() async => _preferences.getString(_storageKey);

  @override
  Future<void> write(String value) async {
    await _preferences.setString(_storageKey, value);
  }
}
