import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/push/push_service.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR'); // tarihler için TR yerelleştirme
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Push servisi ile aynı Riverpod container'ını paylaşmak için elle oluşturuyoruz.
  final container = ProviderContainer();

  // Firebase init (hızlı) — eksik/hatalıysa loglanır, uygulama yine açılır.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    if (kDebugMode) debugPrint('[push] Firebase init başarısız: $e');
  }

  // UI'yi HEMEN aç. Push başlatma (izin isteği + token kaydı) arka planda çalışır;
  // ağ/izin bekletirse uygulama açılışını KİLİTLEMESİN (siyah ekran olmasın).
  runApp(UncontrolledProviderScope(
    container: container,
    child: const FerxgoApp(),
  ));

  Future.microtask(() async {
    try {
      await container.read(pushServiceProvider).start();
    } catch (e) {
      if (kDebugMode) debugPrint('[push] başlatma atlandı: $e');
    }
  });
}

class FerxgoApp extends ConsumerWidget {
  const FerxgoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FerXGo',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: FerxgoTheme.light(),
      darkTheme: FerxgoTheme.dark(),
      themeMode: ThemeMode.dark, // mobil için varsayılan koyu
      routerConfig: router,
    );
  }
}
