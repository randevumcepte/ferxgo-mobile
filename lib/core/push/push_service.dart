import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_controller.dart';
import '../routing/app_router.dart';

/// Foreground bildirimlerini SnackBar ile göstermek için global messenger key.
/// main.dart'ta MaterialApp.router'a `scaffoldMessengerKey` olarak verilir.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Uygulama arka planda / kapalıyken gelen mesaj için top-level handler.
/// Bildirim (notification) mesajlarını sistem tepsisi zaten gösterir; burada
/// ekstra iş yok. Sadece data-only mesajda arka plan işi gerekirse eklenir.
///
/// main() içinde: FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // no-op (MVP)
}

/// FCM yaşam döngüsü yöneticisi.
///  - Bildirim izni ister (iOS + Android 13+)
///  - FCM token'ı alır ve backend'e (POST /devices/push-token) kaydeder
///  - Token yenilenince yeniden kaydeder
///  - Foreground mesajı SnackBar gösterir, tıklanınca deep-link yapar
///  - Bildirime tıklayıp açılmayı (arka plan + soğuk başlangıç) yönlendirir
class PushService {
  PushService(this._ref);

  final Ref _ref;
  bool _started = false;
  String? _lastSyncedToken;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  /// main() içinde Firebase.initializeApp SONRASI bir kez çağrılır.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // Token yenilendiğinde tekrar kaydet.
    _fm.onTokenRefresh.listen((token) {
      _lastSyncedToken = null;
      syncToken(token: token);
    });

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);

    // Uygulama kapalıyken bildirime tıklanıp açıldıysa.
    final initial = await _fm.getInitialMessage();
    if (initial != null) _onOpened(initial);

    // Zaten oturum açıksa (uygulama yeniden açıldı) token'ı hemen kaydet.
    if (_ref.read(authControllerProvider).value != null) {
      unawaited(syncToken());
    }
  }

  /// FCM token'ı backend'e kaydeder. Yalnızca oturum açıkken anlamlı — endpoint
  /// önce login'de yaratılan device kaydını ister; yoksa 404 döner ve sessizce
  /// yutulur (bir sonraki login / token refresh yeniden dener).
  ///
  /// Login akışından (auth_repository, set() sonrası) da çağrılır.
  Future<void> syncToken({String? token}) async {
    try {
      if (_ref.read(authControllerProvider).value == null) return;

      final t = token ?? await _fm.getToken();
      if (t == null || t.length < 32) return;
      if (t == _lastSyncedToken) return;

      await _ref.read(apiClientProvider).postJson(
        'devices/push-token',
        body: {'fcm_token': t},
      );
      _lastSyncedToken = t;
      if (kDebugMode) debugPrint('[push] token kaydedildi');
    } catch (e) {
      if (kDebugMode) debugPrint('[push] token sync atlandı: $e');
    }
  }

  void _onForeground(RemoteMessage m) {
    final n = m.notification;
    final messenger = rootScaffoldMessengerKey.currentState;
    if (n == null || messenger == null) return;

    final title = n.title;
    final text = title != null && title.isNotEmpty
        ? '$title: ${n.body ?? ''}'
        : (n.body ?? 'Yeni bildirim');

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(label: 'Aç', onPressed: () => _route(m.data)),
      ));
  }

  void _onOpened(RemoteMessage m) => _route(m.data);

  /// data.type'a göre deep-link. Sunucu PushService'inde gönderilen tiplerle eşleşir.
  ///   Müşteri: ride_update / offer_update / new_message_customer → tracking ekranı
  ///   Sürücü : new_request / new_offer / new_message_driver       → sürücü ana ekranı
  void _route(Map<String, dynamic> data) {
    final router = _ref.read(appRouterProvider);
    final type = (data['type'] ?? '').toString();
    final publicId =
        (data['ride_public_id'] ?? data['public_id'] ?? '').toString();

    switch (type) {
      case 'ride_update':
      case 'offer_update':
      case 'new_message_customer':
        if (publicId.isNotEmpty) {
          router.go('${AppRoutes.customerRideBase}/$publicId');
        }
        break;
      case 'new_request':
      case 'new_offer':
      case 'new_message_driver':
        router.go(AppRoutes.driverHome);
        break;
      default:
        break;
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));
