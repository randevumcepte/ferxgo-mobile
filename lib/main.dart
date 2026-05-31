import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ProviderScope(child: FerogoApp()));
}

class FerogoApp extends ConsumerWidget {
  const FerogoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Ferogo',
      debugShowCheckedModeBanner: false,
      theme: FerogoTheme.light(),
      darkTheme: FerogoTheme.dark(),
      themeMode: ThemeMode.dark, // mobil için varsayılan koyu
      routerConfig: router,
    );
  }
}
