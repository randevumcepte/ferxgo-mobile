import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Sanctum token, device_id ve diğer hassas değerleri Keychain (iOS) /
/// EncryptedSharedPreferences (Android) üzerinde tutar.
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  // Anahtarlar — tek noktada tutulur ki typo yenmesin.
  static const String kAuthToken     = 'ferxgo.auth.token';
  static const String kAuthTokenExp  = 'ferxgo.auth.expires_at';
  static const String kAuthUserJson  = 'ferxgo.auth.user';
  static const String kDeviceId      = 'ferxgo.device.id';
  static const String kAppMode       = 'ferxgo.app.mode'; // customer | driver

  Future<String?> read(String key) => _storage.read(key: key);
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Çıkış / token revoke sonrası tüm auth anahtarlarını sil.
  /// Device id KALMAZ silinmez — aynı cihaz tekrar login olduğunda backend
  /// bunu tanımalı (cihaz bazlı revoke için).
  Future<void> clearAuth() async {
    await Future.wait([
      _storage.delete(key: kAuthToken),
      _storage.delete(key: kAuthTokenExp),
      _storage.delete(key: kAuthUserJson),
    ]);
  }
}

final secureStorageProvider = Provider<SecureStorage>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  return SecureStorage(storage);
});
