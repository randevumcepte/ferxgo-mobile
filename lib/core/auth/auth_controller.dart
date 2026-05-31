import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import 'auth_state.dart';

/// AuthController — uygulamanın oturum durumunu yönetir.
///
/// State:
///  - null = "henüz okunmadı" (splash)
///  - AuthSession = aktif oturum
///  - AsyncValue.error / data(null) = logged out
///
/// Splash ekranı bunu watch eder; data geldiğinde router yönlendirir.
class AuthController extends AsyncNotifier<AuthSession?> {
  late final SecureStorage _storage = ref.read(secureStorageProvider);

  @override
  Future<AuthSession?> build() async {
    final raw = await _storage.read(SecureStorage.kAuthUserJson);
    if (raw == null) return null;
    try {
      final session = AuthSession.decode(raw);
      if (session.isExpired) {
        await _storage.clearAuth();
        return null;
      }
      return session;
    } catch (_) {
      await _storage.clearAuth();
      return null;
    }
  }

  /// Yeni token + user'ı yaz, state'i güncelle.
  /// Login flow'larından (OTP verify, driver login) çağrılır.
  Future<void> set(AuthSession session) async {
    await _storage.write(SecureStorage.kAuthUserJson, session.encode());
    await _storage.write(SecureStorage.kAuthToken, session.token);
    if (session.expiresAt != null) {
      await _storage.write(SecureStorage.kAuthTokenExp, session.expiresAt!.toIso8601String());
    }
    state = AsyncData(session);
  }

  /// Lokal logout — token'ı siler. Backend'e /auth/logout sonra çağrılır (opsiyonel).
  Future<void> clear() async {
    await _storage.clearAuth();
    state = const AsyncData(null);
  }

  AuthSession? get current => state.value;
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
