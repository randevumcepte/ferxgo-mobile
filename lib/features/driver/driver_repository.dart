import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../customer/models/ride_status.dart' show RideMessage;
import 'models/driver_state.dart';

/// Mobil sürücü paneli API katmanı — `/driver/*` uçları.
class DriverRepository {
  DriverRepository(this._api);

  final ApiClient _api;

  /// Tek endpoint polling: driver + offer + active + messages.
  Future<DriverState> state({int sinceId = 0}) async {
    final res = await _api.getJson('/driver/state', query: {'since_id': sinceId});
    return DriverState.fromJson(res);
  }

  /// Çevrimiçi / çevrimdışı — konum verilirse birlikte kaydedilir.
  Future<String> setAvailability(String status, {double? lat, double? lng}) async {
    final res = await _api.postJson('/driver/availability', body: {
      'status': status,
      'lat': ?lat,
      'lng': ?lng,
    });
    return (res['status'] as String?) ?? status;
  }

  /// "Sadece kadın yolcu al" (yalnızca kadın sürücüler).
  Future<bool> setWomenOnly(bool enabled) async {
    final res = await _api.postJson('/driver/women-only', body: {'enabled': enabled});
    return (res['women_only'] as bool?) ?? enabled;
  }

  /// Periyodik konum güncellemesi (online iken, ~20-30 sn'de bir).
  Future<void> updateLocation(double lat, double lng) async {
    await _api.postJson('/driver/location', body: {'lat': lat, 'lng': lng});
  }

  // ─── Teklifler ────────────────────────────────────────────
  Future<void> acceptOffer(String publicId) async {
    await _api.postJson('/driver/offers/$publicId/accept');
  }

  Future<void> counterOffer(String publicId, double amount) async {
    await _api.postJson('/driver/offers/$publicId/counter', body: {'amount': amount});
  }

  Future<void> rejectOffer(String publicId) async {
    await _api.postJson('/driver/offers/$publicId/reject');
  }

  // ─── Aktif yolculuk ───────────────────────────────────────
  Future<void> markArrived() async {
    await _api.postJson('/driver/active/arrived');
  }

  Future<void> reportNoShow({double? lat, double? lng, String? note}) async {
    await _api.postJson('/driver/active/no-show', body: {
      'lat': ?lat,
      'lng': ?lng,
      'note': ?note,
    });
  }

  Future<void> completeRide() async {
    await _api.postJson('/driver/active/complete');
  }

  Future<RideMessage> sendMessage(String body) async {
    final res = await _api.postJson('/driver/active/message', body: {'body': body});
    return RideMessage.fromJson((res['message'] as Map).cast<String, dynamic>());
  }
}

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  return DriverRepository(ref.watch(apiClientProvider));
});
