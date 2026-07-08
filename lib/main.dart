import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR'); // tarihler için TR yerelleştirme
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ProviderScope(child: FerxgoApp()));
}

class FerxgoApp extends ConsumerWidget {
  const FerxgoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FerXGo',
      debugShowCheckedModeBanner: false,
      theme: FerxgoTheme.light(),
      darkTheme: FerxgoTheme.dark(),
      themeMode: ThemeMode.dark, // mobil için varsayılan koyu
      routerConfig: router,
    );
  }
}
