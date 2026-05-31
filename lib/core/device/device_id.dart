import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../storage/secure_storage.dart';

/// Cihazın benzersiz kimliği. İlk açılışta üretilir, secure storage'a yazılır.
///
/// Backend'deki TouchDevice middleware'i bu id'yi her authed istekte
/// `X-Device-Id` header'ında bekler. Token bu id ile bağlıdır;
/// başka id ile gelirse derhal revoke edilir.
///
/// Uygulama silinip yeniden kurulursa yeni id üretilir — yeni login gerekir.
class DeviceIdService {
  DeviceIdService(this._storage);

  final SecureStorage _storage;
  String? _cached;

  Future<String> ensure() async {
    if (_cached != null) return _cached!;

    final existing = await _storage.read(SecureStorage.kDeviceId);
    if (existing != null && existing.length >= 16) {
      _cached = existing;
      return existing;
    }

    final generated = _generate();
    await _storage.write(SecureStorage.kDeviceId, generated);
    _cached = generated;
    return generated;
  }

  /// Test/debug için: device_id'yi sıfırla. Token'lar revoke olur.
  Future<void> reset() async {
    await _storage.delete(SecureStorage.kDeviceId);
    _cached = null;
  }

  String _generate() {
    // UUID v4 — 32 hex char (tire çıkar). 'ferd_' prefix'i debug'ta yardımcı olur.
    final raw = const Uuid().v4().replaceAll('-', '');
    return 'ferd_$raw'; // 5 + 32 = 37 char (max 64 backend limit'i içinde)
  }
}

final deviceIdServiceProvider = Provider<DeviceIdService>((ref) {
  return DeviceIdService(ref.watch(secureStorageProvider));
});

/// Convenience: bir kere okur, cache'ler. Çoğu yerde direkt bunu await edersin.
final deviceIdProvider = FutureProvider<String>((ref) async {
  return ref.watch(deviceIdServiceProvider).ensure();
});
