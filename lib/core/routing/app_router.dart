import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/app_mode/app_mode.dart';
import '../../features/auth/screens/customer_otp_screen.dart';
import '../../features/auth/screens/customer_phone_screen.dart';
import '../../features/auth/screens/driver_login_screen.dart';
import '../../features/customer/screens/booking_confirm_screen.dart';
import '../../features/customer/screens/customer_history_screen.dart';
import '../../features/customer/screens/customer_map_screen.dart';
import '../../features/customer/screens/dropoff_search_screen.dart';
import '../../features/customer/screens/ride_tracking_screen.dart';
import '../../features/driver/screens/driver_home_screen.dart';
import '../../features/mode_select/mode_select_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../auth/auth_controller.dart';

class AppRoutes {
  AppRoutes._();

  static const splash         = '/';
  static const modeSelect     = '/mode';
  static const customerPhone  = '/customer/phone';
  static const customerOtp    = '/customer/otp';
  static const driverLogin    = '/driver/login';
  static const customerHome           = '/customer/home';     // ana ekran (harita)
  static const customerHistory        = '/customer/history';
  static const customerBookDropoff    = '/customer/book/dropoff';
  static const customerBookConfirm    = '/customer/book/confirm';
  /// Tracking URL: `$customerRideBase/$publicId`
  static const customerRideBase       = '/customer/ride';
  static const driverHome             = '/driver/home';
  static const profile                = '/profile';
}

/// Router auth state ve mod seçimini watch eder, ona göre redirect yapar.
///
/// Akış:
///   - auth.loading  → splash kalsın
///   - auth.value=null + mode=null  → /mode
///   - auth.value=null + mode=customer → /customer/phone
///   - auth.value=null + mode=driver   → /driver/login
///   - auth.value!=null user.isCustomer → /customer/home
///   - auth.value!=null user.isDriver   → /driver/home
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterRefresh(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final mode = ref.read(appModeControllerProvider);

      // Henüz okumadık — splash'da dur
      if (auth.isLoading || mode.isLoading) {
        return state.matchedLocation == AppRoutes.splash ? null : AppRoutes.splash;
      }

      final session = auth.value;
      final appMode = mode.value;
      final loc     = state.matchedLocation;

      // Login olmuş kullanıcı
      if (session != null) {
        final target = session.user.isDriver ? AppRoutes.driverHome : AppRoutes.customerHome;
        // Halen splash/login ekranlarındaysa home'a fırlat
        const authPages = {
          AppRoutes.splash,
          AppRoutes.modeSelect,
          AppRoutes.customerPhone,
          AppRoutes.customerOtp,
          AppRoutes.driverLogin,
        };
        if (authPages.contains(loc)) return target;
        return null;
      }

      // Login olmamış
      if (appMode == null) {
        return loc == AppRoutes.modeSelect ? null : AppRoutes.modeSelect;
      }

      // Mod var, login yok — uygun login ekranına yönlendir.
      // Not: modeSelect ALLOWED değil — kullanıcı mod seçtiğinde derhal
      // login akışına geçer. Mod değiştirmek isterse appModeController.clear()
      // (örn. login ekranındaki "geri" butonu) çağrılır → appMode null olur,
      // yukarıdaki bloktan modeSelect'e atılır.
      final loginEntry = appMode == AppMode.driver
          ? AppRoutes.driverLogin
          : AppRoutes.customerPhone;

      // Müşteri akışı: phone ↔ otp arasında geçiş serbest
      // Sürücü akışı: sadece driverLogin
      final allowedForCurrentMode = appMode == AppMode.driver
          ? const {AppRoutes.driverLogin}
          : const {AppRoutes.customerPhone, AppRoutes.customerOtp};

      if (allowedForCurrentMode.contains(loc)) return null;
      return loginEntry;
    },
    routes: [
      GoRoute(path: AppRoutes.splash,        builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.modeSelect,    builder: (_, _) => const ModeSelectScreen()),
      GoRoute(path: AppRoutes.customerPhone, builder: (_, _) => const CustomerPhoneScreen()),
      GoRoute(
        path: AppRoutes.customerOtp,
        builder: (_, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          return CustomerOtpScreen(phone: phone);
        },
      ),
      GoRoute(path: AppRoutes.driverLogin,         builder: (_, _) => const DriverLoginScreen()),
      GoRoute(path: AppRoutes.customerHome,        builder: (_, _) => const CustomerMapScreen()),
      GoRoute(path: AppRoutes.customerHistory,     builder: (_, _) => const CustomerHistoryScreen()),
      GoRoute(path: AppRoutes.customerBookDropoff, builder: (_, _) => const DropoffSearchScreen()),
      GoRoute(path: AppRoutes.customerBookConfirm, builder: (_, _) => const BookingConfirmScreen()),
      GoRoute(
        path: '${AppRoutes.customerRideBase}/:publicId',
        builder: (_, state) => RideTrackingScreen(
          publicId: state.pathParameters['publicId']!,
        ),
      ),
      GoRoute(path: AppRoutes.driverHome,          builder: (_, _) => const DriverHomeScreen()),
      GoRoute(path: AppRoutes.profile,             builder: (_, _) => const ProfileScreen()),
    ],
  );
});

/// Auth/mode state'leri değiştiğinde GoRouter'ı yeniden değerlendirir.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this._ref) {
    _ref.listen(authControllerProvider, (_, _) => notifyListeners());
    _ref.listen(appModeControllerProvider, (_, _) => notifyListeners());
  }
  final Ref _ref;
}
