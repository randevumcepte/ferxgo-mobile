/// Build-time sabitler. Üretimde `--dart-define` ile override edilebilir:
///   flutter run --dart-define=FERXGO_API_BASE=https://staging.example.com/api/v1
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'FERXGO_API_BASE',
    defaultValue: 'https://appnew.randevumcepte.com.tr/api/v1',
  );

  /// Yer arama, polling vb. için kullanılır.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Talep durumu polling kadansı (web ile aynı).
  static const Duration ridePollInterval = Duration(seconds: 2);

  /// Sürücü state polling kadansı.
  static const Duration driverPollInterval = Duration(seconds: 3);
}
