import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_client.dart';
import 'models/nearby_driver.dart';
import 'models/ride_history_item.dart';

class CustomerRideRepository {
  CustomerRideRepository(this._api);

  final ApiClient _api;

  Future<NearbyResult> nearbyDrivers({
    required double lat,
    required double lng,
    int limit = 6,
  }) async {
    final res = await _api.getJson('/customer/drivers/nearby', query: {
      'lat': lat,
      'lng': lng,
      'limit': limit,
    });

    final list = (res['drivers'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => NearbyDriver.fromJson(
              Map<String, dynamic>.from(m),
              fallback: LatLng(lat, lng),
            ))
        .toList(growable: false);

    final totalOnline = (res['total_online'] as num?)?.toInt() ?? 0;

    return NearbyResult(drivers: list, totalOnline: totalOnline);
  }

  Future<List<RideHistoryItem>> history({int limit = 20}) async {
    final res = await _api.getJson('/customer/history', query: {'limit': limit});
    final list = (res['rides'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => RideHistoryItem.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return list;
  }
}

class NearbyResult {
  const NearbyResult({required this.drivers, required this.totalOnline});
  final List<NearbyDriver> drivers;
  final int totalOnline;
}

final customerRideRepositoryProvider = Provider<CustomerRideRepository>((ref) {
  return CustomerRideRepository(ref.watch(apiClientProvider));
});
