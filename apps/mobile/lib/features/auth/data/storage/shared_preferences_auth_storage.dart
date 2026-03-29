import 'package:shared_preferences/shared_preferences.dart';
import 'package:wishiz/features/auth/data/storage/auth_storage.dart';

class SharedPreferencesAuthStorage implements AuthStorage {
  SharedPreferencesAuthStorage._(this._preferences);

  static const String _storageKey = 'wishiz.auth';

  final SharedPreferences _preferences;

  static Future<SharedPreferencesAuthStorage> create() async {
    final preferences = await SharedPreferences.getInstance();
    return SharedPreferencesAuthStorage._(preferences);
  }

  @override
  Future<String?> read() async => _preferences.getString(_storageKey);

  @override
  Future<void> write(String value) async {
    await _preferences.setString(_storageKey, value);
  }
}
