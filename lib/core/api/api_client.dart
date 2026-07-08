import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'interceptors/auth_device_interceptor.dart';

/// FerXGo Mobile API client (Dio).
///
/// Sözleşme (docs/MOBILE_API.md):
///  - Base URL: AppConfig.apiBaseUrl
///  - Tüm yanıtlar JSON `{ok: bool, ...}` zarfında
///  - Hatada Map içerikten ApiException üretiriz; çağıran try/catch eder.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;
  Dio get raw => _dio;

  /// ok:true zarfında "anahtar" varsa onu, yoksa tam map'i döner.
  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) =>
      _request('GET', path, query: query);

  Future<Map<String, dynamic>> postJson(String path,
          {Map<String, dynamic>? body, Map<String, dynamic>? query}) =>
      _request('POST', path, body: body, query: query);

  Future<Map<String, dynamic>> deleteJson(String path, {Map<String, dynamic>? query}) =>
      _request('DELETE', path, query: query);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      // İşte sunucu beklenmedik bir şey döndü.
      throw ApiException(
        message: 'Sunucudan beklenmedik yanıt.',
        statusCode: res.statusCode ?? 0,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: AppConfig.defaultTimeout,
    receiveTimeout: AppConfig.defaultTimeout,
    sendTimeout: AppConfig.defaultTimeout,
    responseType: ResponseType.json,
    headers: {
      HttpHeaders.userAgentHeader: _userAgent(),
    },
  ));

  dio.interceptors.add(AuthDeviceInterceptor(ref));

  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      requestHeader: false,
      responseHeader: false,
      logPrint: (o) => debugPrint('[dio] $o'),
    ));
  }

  return ApiClient(dio);
});

String _userAgent() => 'FerXGo-Mobile/0.1.0 (Dart/Dio)';
