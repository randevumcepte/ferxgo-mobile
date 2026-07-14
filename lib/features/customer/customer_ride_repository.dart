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

  // ─── Yer arama (GeoService: Yandex/Photon/Nominatim) ──────
  Future<List<Place>> searchPlaces(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 2) return const [];
    final res = await _api.getJson('/customer/places/search', query: {'q': trimmed});
    return (res['results'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Place.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }

  /// Koordinatsız (Yandex) öneriyi seçince gerçek konumu çöz.
  /// [uri] Yandex önerisinin uri'si; yoksa [text] ile metinden çözülür.
  Future<Place?> resolvePlace({String? uri, String? text}) async {
    final res = await _api.getJson('/customer/places/resolve', query: {
      if (uri != null && uri.isNotEmpty) 'uri': uri,
      if (text != null && text.isNotEmpty) 'text': text,
    });
    final lat = (res['lat'] as num?)?.toDouble();
    final lon = (res['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return Place(
      position: LatLng(lat, lon),
      displayName: res['display_name'] as String? ?? (text ?? ''),
      hasCoords: true,
    );
  }

  /// İki nokta arası gerçek sürüş rotası (yol çizgisi + mesafe/süre). OSRM proxy.
  Future<RouteResult?> route({required LatLng from, required LatLng to}) async {
    try {
      final res = await _api.getJson('/customer/route', query: {
        'from_lat': from.latitude,
        'from_lng': from.longitude,
        'to_lat': to.latitude,
        'to_lng': to.longitude,
      });
      final raw = (res['points'] as List? ?? const []);
      final points = raw
          .whereType<List>()
          .where((p) => p.length >= 2)
          .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(growable: false);
      if (points.isEmpty) return null;
      return RouteResult(
        points: points,
        distanceKm: (res['distance_km'] as num?)?.toDouble() ?? 0,
        durationMin: (res['duration_min'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
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
    double? suggestedFare,
    double? customerOfferFare,
    int? preferredDriverId,
    List<int> fallbackDriverIds = const [],
    /// 'auto' (tümü) | 'nearby' (yakın havuz) | 'pool' (seçili liste) | null (1:1)
    String? dispatchMode,
    /// dispatch_mode=pool için seçili sürücü id listesi
    List<int>? driverIds,
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
      'suggested_fare':  ?suggestedFare,
      'customer_offer_fare': ?customerOfferFare,
      'dispatch_mode':   ?dispatchMode,
      'preferred_driver_id': ?preferredDriverId,
      'fallback_driver_ids': fallbackDriverIds,
      'driver_ids': ?driverIds,
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

  /// Faz 6 — görsel doğrulama: yolculuk başladıktan sonra müşteri
  /// "araç/sürücü doğru mu?" cevabı verir. match=false → güvenlik olayı açılır.
  /// Dönen map: { ok, verified, message, incident_id?, status }.
  Future<Map<String, dynamic>> visualVerify(String publicId, bool match, {String? note}) async {
    return _api.postJson('/customer/ride-requests/$publicId/visual-verify', body: {
      'match': match,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  // ─── Fiyat pazarlığı ──────────────────────────────────────
  /// Müşteri sürücünün karşı teklifine yeni fiyat verir.
  Future<void> counterPrice(String publicId, double amount) async {
    await _api.postJson('/customer/ride-requests/$publicId/counter',
        body: {'amount': amount});
  }

  /// Müşteri sürücünün karşı teklifini kabul eder → yolculuk başlar.
  Future<RideStatus> acceptPrice(String publicId, LatLng fallback) async {
    final res = await _api.postJson('/customer/ride-requests/$publicId/accept-price');
    return RideStatus.fromJson(
      (res['status'] as Map).cast<String, dynamic>(),
      fallbackPosition: fallback,
    );
  }

  // ─── Auto/havuz akışı ("Hadi Gidelim") ────────────────────
  /// Eşleşen üye sürücüyü onayla (accept=true) ya da reddet (false).
  Future<RideStatus> reconfirm(String publicId, bool accept, LatLng fallback) async {
    final res = await _api.postJson('/customer/ride-requests/$publicId/reconfirm',
        body: {'accept': accept});
    return RideStatus.fromJson(
      (res['status'] as Map).cast<String, dynamic>(),
      fallbackPosition: fallback,
    );
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

/// OSRM sürüş rotası — yol çizgisi noktaları + gerçek mesafe/süre.
class RouteResult {
  const RouteResult({required this.points, required this.distanceKm, required this.durationMin});
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
}

final customerRideRepositoryProvider = Provider<CustomerRideRepository>((ref) {
  return CustomerRideRepository(ref.watch(apiClientProvider));
});
