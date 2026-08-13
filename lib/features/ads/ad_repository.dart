import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import 'models/ad.dart';

/// Reklam slot sabitleri — backend `Advertisement::PLACEMENTS` ile birebir.
class AdPlacements {
  AdPlacements._();

  static const String homeBanner = 'home_banner';
  static const String rideTracking = 'ride_tracking';
  static const String radarMap = 'radar_map';
  static const String radarSidebar = 'radar_sidebar';
  static const String driverPanel = 'driver_panel';
  static const String popup = 'popup';
}

/// Marketing modülünün mobil API karşılığı.
/// `/ads` slot bazlı reklam döndürür (gösterim otomatik kaydedilir); tıklama
/// ayrı endpoint ile kaydedilip hedef link geri alınır.
class AdRepository {
  AdRepository(this._api);

  final ApiClient _api;

  /// Birden çok slot için aktif reklamları tek çağrıda getirir.
  /// Dönen map her placement için `Ad` ya da null içerir. Gösterim (impression)
  /// sunucu tarafında kaydedilir — yalnızca gerçekten göstereceğin slotları iste.
  Future<Map<String, Ad?>> fetch(
    List<String> placements, {
    double? lat,
    double? lng,
  }) async {
    if (placements.isEmpty) return const {};

    final res = await _api.getJson('/ads', query: {
      'placements': placements.join(','),
      'lat': ?lat,
      'lng': ?lng,
    });

    final raw = (res['ads'] as Map?)?.cast<String, dynamic>() ?? const {};
    final out = <String, Ad?>{};
    for (final placement in placements) {
      final item = raw[placement];
      out[placement] = item is Map
          ? Ad.fromJson(Map<String, dynamic>.from(item))
          : null;
    }
    return out;
  }

  /// Tek slot için kısayol.
  Future<Ad?> fetchOne(String placement, {double? lat, double? lng}) async {
    final map = await fetch([placement], lat: lat, lng: lng);
    return map[placement];
  }

  /// Tıklamayı kaydeder ve reklamın hedef linkini döndürür (istemci açar).
  Future<String?> registerClick(int adId, {double? lat, double? lng}) async {
    final res = await _api.postJson('/ads/$adId/click', body: {
      'lat': ?lat,
      'lng': ?lng,
    });
    return res['link_url'] as String?;
  }
}

final adRepositoryProvider = Provider<AdRepository>((ref) {
  return AdRepository(ref.watch(apiClientProvider));
});
