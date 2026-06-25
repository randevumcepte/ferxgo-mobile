import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_client.dart';
import 'models/nearby_driver.dart';
import 'models/place.dart';
import 'models/ride_history_item.dart';
import 'models/ride_status.dart';
import 'models/vehicle_class.dart';

class CustomerRideRepository {
  CustomerRideRepository(this._api);

  final ApiClient _api;

  // ─── Bootstrap (vehicle classes vs.) ──────────────────────
  Future<List<VehicleClassRef>> vehicleClasses() async {
    final res = await _api.getJson('/customer/bootstrap');
    final list = (res['vehicle_classes'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => VehicleClassRef.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return list;
  }

  // ─── Yakındaki sürücüler ──────────────────────────────────
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

    return NearbyResult(
      drivers: list,
      totalOnline: (res['total_online'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, dynamic>> driverProfile(int driverId) async {
    final res = await _api.getJson('/customer/drivers/$driverId/profile');
    return (res['driver'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  // ─── Favori sürücüler ("tekrar onu çağır") ────────────────
  Future<List<NearbyDriver>> favorites() async {
    final res = await _api.getJson('/customer/favorites');
    return (res['drivers'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => NearbyDriver.fromJson(
              Map<String, dynamic>.from(m),
              fallback: const LatLng(38.4237, 27.1428), // İzmir merkez
            ))
        .toList(growable: false);
  }

  /// Favoriye ekle. Backend `favorited: true/false` döner.
  Future<bool> addFavorite(int driverId) async {
    final res = await _api.postJson('/customer/favorites/$driverId');
    return (res['favorited'] as bool?) ?? true;
  }

  /// Favoriden çıkar.
  Future<bool> removeFavorite(int driverId) async {
    final res = await _api.deleteJson('/customer/favorites/$driverId');
    return (res['favorited'] as bool?) ?? false;
  }

  // ─── Yer arama (Nominatim proxy) ──────────────────────────
  Future<List<Place>> searchPlaces(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 2) return const [];
    final res = await _api.getJson('/customer/places/search', query: {'q': trimmed});
    return (res['results'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Place.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  // ─── Fiyat hesabı ─────────────────────────────────────────
  Future<Map<String, dynamic>> calculateFare({
    required int vehicleClassId,
    required double distanceKm,
    required int durationMinutes,
  }) async {
    final res = await _api.postJson('/customer/fare/calculate', body: {
      'vehicle_class_id': vehicleClassId,
      'distance_km': distanceKm,
      'duration_minutes': durationMinutes,
    });
    return (res['fare'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  // ─── Ride request CRUD ────────────────────────────────────
  Future<({String publicId, RideStatus status})> createRequest({
    required String vehicleClassSlug,
    required String pickupAddress,
    required LatLng pickupPosition,
    required String dropoffAddress,
    required LatLng dropoffPosition,
    required double distanceKm,
    required int durationMinutes,
    double? estimatedFare,
    required int preferredDriverId,
    List<int> fallbackDriverIds = const [],
  }) async {
    final res = await _api.postJson('/customer/ride-requests', body: {
      'vehicle_class_slug': vehicleClassSlug,
      'pickup_address':  pickupAddress,
      'pickup_lat':      pickupPosition.latitude,
      'pickup_lng':      pickupPosition.longitude,
      'dropoff_address': dropoffAddress,
      'dropoff_lat':     dropoffPosition.latitude,
      'dropoff_lng':     dropoffPosition.longitude,
      'distance_km':     distanceKm,
      'duration_minutes':durationMinutes,
      'estimated_fare':  ?estimatedFare,
      'preferred_driver_id': preferredDriverId,
      'fallback_driver_ids': fallbackDriverIds,
      'kvkk_consent': true,
    });

    final publicId = res['public_id'] as String;
    final status = RideStatus.fromJson(
      (res['status'] as Map).cast<String, dynamic>(),
      fallbackPosition: pickupPosition,
    );
    return (publicId: publicId, status: status);
  }

  Future<RideStatus> showRequest(String publicId, LatLng fallback) async {
    final res = await _api.getJson('/customer/ride-requests/$publicId');
    return RideStatus.fromJson(
      (res['status'] as Map).cast<String, dynamic>(),
      fallbackPosition: fallback,
    );
  }

  Future<RideStatus> cancelRequest(String publicId, LatLng fallback) async {
    final res = await _api.postJson('/customer/ride-requests/$publicId/cancel');
    return RideStatus.fromJson(
      (res['status'] as Map).cast<String, dynamic>(),
      fallbackPosition: fallback,
    );
  }

  Future<Map<String, dynamic>> confirmRequest(String publicId) async {
    return _api.postJson('/customer/ride-requests/$publicId/confirm');
  }

  Future<List<RideMessage>> messages(String publicId, {int sinceId = 0}) async {
    final res = await _api.getJson('/customer/ride-requests/$publicId/messages',
        query: {'since_id': sinceId});
    return (res['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => RideMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  Future<RideMessage> sendMessage(String publicId, String body) async {
    final res = await _api.postJson('/customer/ride-requests/$publicId/messages',
        body: {'body': body});
    return RideMessage.fromJson((res['message'] as Map).cast<String, dynamic>());
  }

  // ─── Geçmiş ───────────────────────────────────────────────
  Future<List<RideHistoryItem>> history({int limit = 20}) async {
    final res = await _api.getJson('/customer/history', query: {'limit': limit});
    return (res['rides'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => RideHistoryItem.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
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
