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

  // Firebase + FCM push. Native config dosyaları:
  //   Android: android/app/google-services.json
  //   iOS:     ios/Runner/GoogleService-Info.plist
  // eksik/hatalıysa init loglanır ama uygulama yine açılır (push devre dışı kalır).
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    if (kDebugMode) debugPrint('[push] Firebase init başarısız: $e');
  }

  // Push servisi ile aynı Riverpod container'ını paylaşmak için elle oluşturuyoruz.
  final container = ProviderContainer();
  try {
    await container.read(pushServiceProvider).start();
  } catch (e) {
    if (kDebugMode) debugPrint('[push] başlatma atlandı: $e');
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const FerxgoApp(),
  ));
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
