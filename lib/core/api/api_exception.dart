import 'package:dio/dio.dart';

/// Backend'in standart hata zarfı:
///   { ok: false, message: "...", code?: "...", errors?: {...}, retry_after?: 12 }
class ApiException implements Exception {
  ApiException({
    required this.message,
    required this.statusCode,
    this.code,
    this.errors,
    this.retryAfter,
  });

  final String message;
  final int statusCode;
  final String? code;
  final Map<String, dynamic>? errors;
  final int? retryAfter;

  bool get isUnauthorized => statusCode == 401;
  bool get isTokenRevoked => code == 'token_revoked';
  bool get isRoleMismatch => code == 'role_mismatch';
  bool get isRateLimited  => statusCode == 429;
  bool get isValidation   => statusCode == 422;

  static ApiException fromDio(DioException e) {
    final res = e.response;
    final data = res?.data;

    if (data is Map) {
      return ApiException(
        message: (data['message'] as String?) ?? _fallbackMessage(e),
        statusCode: res?.statusCode ?? 0,
        code: data['code'] as String?,
        errors: data['errors'] is Map ? Map<String, dynamic>.from(data['errors'] as Map) : null,
        retryAfter: (data['retry_after'] as num?)?.toInt(),
      );
    }

    return ApiException(
      message: _fallbackMessage(e),
      statusCode: res?.statusCode ?? 0,
    );
  }

  static String _fallbackMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Bağlantı zaman aşımına uğradı. Tekrar dene.';
      case DioExceptionType.connectionError:
        return 'İnternete bağlanamadık. Ağını kontrol et.';
      case DioExceptionType.badCertificate:
        return 'Güvenli bağlantı kurulamadı.';
      case DioExceptionType.cancel:
        return 'İstek iptal edildi.';
      case DioExceptionType.badResponse:
        return 'Sunucu hatası.';
      case DioExceptionType.unknown:
        return 'Beklenmedik bir hata oldu.';
    }
  }

  @override
  String toString() => 'ApiException($statusCode${code != null ? '/$code' : ''}): $message';
}
