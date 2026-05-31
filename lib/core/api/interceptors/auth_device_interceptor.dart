import 'package:dio/dio.dart';

import '../../auth/auth_controller.dart';
import '../../device/device_id.dart';
import '../../storage/secure_storage.dart';

/// Her isteğe:
///   - `Authorization: Bearer <token>`   (varsa)
///   - `X-Device-Id: <device_id>`        (her zaman)
///   - `Accept: application/json`
/// Cevapta:
///   - 401 + code:token_revoked => oturumu tamamen temizle (router login'e atar)
class AuthDeviceInterceptor extends Interceptor {
  AuthDeviceInterceptor(this._ref) : super();

  // Riverpod Ref — handler içinde container'a erişmek için.
  // Burada ProviderContainer ya da Ref pas edilebilir; biz Ref kullanıyoruz.
  final dynamic _ref;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    options.headers['Accept'] = 'application/json';

    final storage = _ref.read(secureStorageProvider) as SecureStorage;
    final token   = await storage.read(SecureStorage.kAuthToken);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    final deviceId = await (_ref.read(deviceIdServiceProvider) as DeviceIdService).ensure();
    options.headers['X-Device-Id'] = deviceId;

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final res  = err.response;
    final code = res?.data is Map ? (res!.data['code'] as String?) : null;

    if (res?.statusCode == 401 && code == 'token_revoked') {
      // Token cihazdan koparılmış — local'da da sil, splash login'e yönlendirsin
      final controller = _ref.read(authControllerProvider.notifier) as AuthController;
      // Async ama interceptor sync zincirini bekletmiyoruz; fire-and-forget
      // bilinçli: response yine de hata olarak üst katmana gider.
      controller.clear();
    }

    handler.next(err);
  }
}
