import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage.dart';

/// Devam eden (aktif) yolculuğun publicId'si.
///
/// Yolcu bir talep gönderip eşleşince/yolculuk başlayınca burada saklanır.
/// Uygulama kapatılıp yeniden açıldığında bu değer doluysa router yolcuyu
/// doğrudan tracking ekranına döndürür (aktif yolculuğa tekrar erişim).
/// Yolculuk sonlanınca (iptal/red/tamamlandı) temizlenir.
class ActiveRideController extends AsyncNotifier<String?> {
  late final SecureStorage _storage = ref.read(secureStorageProvider);

  @override
  Future<String?> build() async {
    final raw = await _storage.read(SecureStorage.kActiveRide);
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  Future<void> set(String publicId) async {
    if (state.valueOrNull == publicId) return;
    await _storage.write(SecureStorage.kActiveRide, publicId);
    state = AsyncData(publicId);
  }

  Future<void> clear() async {
    if (state.hasValue && state.valueOrNull == null) return;
    await _storage.delete(SecureStorage.kActiveRide);
    state = const AsyncData(null);
  }
}

final activeRideControllerProvider =
    AsyncNotifierProvider<ActiveRideController, String?>(ActiveRideController.new);
