import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/device/device_id.dart';

/// Ferogo mobil auth katmanı — backend Mobile API ile konuşur.
class AuthRepository {
  AuthRepository(this._api, this._ref);

  final ApiClient _api;
  final Ref _ref;

  // ─── Müşteri OTP akışı ────────────────────────────────────

  /// `{ ok, message, dev_code? }`
  Future<Map<String, dynamic>> sendCustomerOtp(String phone) async {
    final deviceId = await _ref.read(deviceIdServiceProvider).ensure();
    return _api.postJson('/auth/customer/send-otp', body: {
      'phone': phone,
      'device_id': deviceId,
    });
  }

  /// Başarılı olursa AuthSession döner ve [AuthController]'a yazar.
  Future<AuthSession> verifyCustomerOtp({
    required String phone,
    required String code,
    String? name,
  }) async {
    final meta = await _deviceMeta();
    final res = await _api.postJson('/auth/customer/verify-otp', body: {
      'phone': phone,
      'code': code,
      ...meta,
      if (name != null && name.isNotEmpty) 'name': name,
    });
    final session = _sessionFromResponse(res);
    await _ref.read(authControllerProvider.notifier).set(session);
    return session;
  }

  // ─── Sürücü login ─────────────────────────────────────────

  Future<AuthSession> driverLogin({
    required String email,
    required String password,
  }) async {
    final meta = await _deviceMeta();
    final res = await _api.postJson('/auth/driver/login', body: {
      'email': email,
      'password': password,
      ...meta,
    });
    final session = _sessionFromResponse(res);
    await _ref.read(authControllerProvider.notifier).set(session);
    return session;
  }

  // ─── /me & /logout ────────────────────────────────────────

  Future<AuthUser> me() async {
    final res = await _api.getJson('/auth/me');
    final user = (res['user'] as Map?)?.cast<String, dynamic>();
    if (user == null) {
      throw StateError('/auth/me sonuçta user yok');
    }
    return AuthUser.fromJson(user);
  }

  /// Backend'e logout, lokal state'i temizle. Backend hatası lokalde takılı kalmasın
  /// diye try/catch.
  Future<void> logout() async {
    try {
      await _api.postJson('/auth/logout');
    } catch (_) {
      // ignore: backend gidişatı belirsiz olabilir; lokal temizliği zorunlu
    }
    await _ref.read(authControllerProvider.notifier).clear();
  }

  // ─── Helpers ──────────────────────────────────────────────

  Future<Map<String, dynamic>> _deviceMeta() async {
    final deviceId = await _ref.read(deviceIdServiceProvider).ensure();
    final pkg      = await PackageInfo.fromPlatform();
    final di       = DeviceInfoPlugin();

    String platform = 'android';
    String? osVersion;
    String? model;
    try {
      if (Platform.isIOS) {
        platform = 'ios';
        final info = await di.iosInfo;
        osVersion = info.systemVersion;
        model = info.utsname.machine;
      } else if (Platform.isAndroid) {
        platform = 'android';
        final info = await di.androidInfo;
        osVersion = info.version.release;
        model = '${info.brand} ${info.model}';
      }
    } catch (_) {/* best-effort */}

    return {
      'device_id'   : deviceId,
      'platform'    : platform,
      'app_version' : pkg.version,
      'os_version'  : ?osVersion,
      'device_model': ?model,
      'locale'      : 'tr-TR',
    };
  }

  AuthSession _sessionFromResponse(Map<String, dynamic> res) {
    final token = res['token'] as String?;
    final user  = (res['user'] as Map?)?.cast<String, dynamic>();
    if (token == null || user == null) {
      throw StateError('Login response token/user içermiyor');
    }
    final expiresAt = res['expires_at'] != null
        ? DateTime.tryParse(res['expires_at'] as String)
        : null;
    return AuthSession(
      token: token,
      user: AuthUser.fromJson(user),
      expiresAt: expiresAt,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider), ref);
});
