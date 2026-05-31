import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/secure_storage.dart';

enum AppMode { customer, driver }

extension AppModeX on AppMode {
  String get value => name; // 'customer' | 'driver'
  static AppMode? parse(String? s) => switch (s) {
        'customer' => AppMode.customer,
        'driver'   => AppMode.driver,
        _          => null,
      };
}

/// Kullanıcının ilk açılışta seçtiği mod. null = henüz seçilmedi.
class AppModeController extends AsyncNotifier<AppMode?> {
  late final SecureStorage _storage = ref.read(secureStorageProvider);

  @override
  Future<AppMode?> build() async {
    final raw = await _storage.read(SecureStorage.kAppMode);
    return AppModeX.parse(raw);
  }

  Future<void> set(AppMode mode) async {
    await _storage.write(SecureStorage.kAppMode, mode.value);
    state = AsyncData(mode);
  }

  Future<void> clear() async {
    await _storage.delete(SecureStorage.kAppMode);
    state = const AsyncData(null);
  }
}

final appModeControllerProvider =
    AsyncNotifierProvider<AppModeController, AppMode?>(AppModeController.new);
