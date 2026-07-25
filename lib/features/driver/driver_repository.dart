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

  /// Sürücünün kendi hakkındaki yolcu değerlendirmeleri (puan + yorum) + ortalama.
  Future<DriverReviews> reviews() async {
    final res = await _api.getJson('/driver/reviews');
    final list = (res['reviews'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => DriverReview.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return DriverReviews(
      average: (res['average'] as num?)?.toDouble() ?? 0,
      count: (res['count'] as num?)?.toInt() ?? 0,
      reviews: list,
    );
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

  /// Görünürlük/hizmet çapı (km, 2..20). Backend 0.5 adımına yuvarlar.
  Future<double> setServiceRadius(double radiusKm) async {
    final res = await _api.postJson('/driver/service-radius', body: {'radius_km': radiusKm});
    return (res['service_radius_km'] as num?)?.toDouble() ?? radiusKm;
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

  /// Yolcunun gösterdiği 4 haneli eşleşme kodunu gir → yolculuğu başlat.
  /// Kod hatalıysa ApiException (422) fırlar.
  Future<void> startWithCode(String code) async {
    await _api.postJson('/driver/active/start-code', body: {'code': code});
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

  /// Aktif yolculuğu iptal et / takılan durumu kapat → sürücü tekrar online.
  Future<void> cancelActive() async {
    await _api.postJson('/driver/active/cancel');
  }

  Future<RideMessage> sendMessage(String body) async {
    final res = await _api.postJson('/driver/active/message', body: {'body': body});
    return RideMessage.fromJson((res['message'] as Map).cast<String, dynamic>());
  }

  /// Sürücünün yaptığı yolculuklar (tamamlanan + iptal), en yenisi üstte.
  Future<DriverHistory> history({int limit = 30}) async {
    final res = await _api.getJson('/driver/history', query: {'limit': limit});
    final items = (res['items'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => DriverRideHistoryItem.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return DriverHistory(
      items: items,
      completedTotal: (res['completed_total'] as num?)?.toInt() ?? 0,
    );
  }
}

final driverRepositoryProvider = Provider<DriverRepository>((ref) {
  return DriverRepository(ref.watch(apiClientProvider));
});

/// Sürücü yolculuk geçmişi (özet + kalemler).
class DriverHistory {
  const DriverHistory({required this.items, required this.completedTotal});
  final List<DriverRideHistoryItem> items;
  final int completedTotal;
}

class DriverRideHistoryItem {
  const DriverRideHistoryItem({
    required this.publicId,
    required this.status,
    required this.isActive,
    this.pickup,
    this.dropoff,
    this.distanceKm,
    this.durationMinutes,
    this.totalFare,
    this.currency,
    this.customerName,
    this.myRating,
    this.completedAt,
    this.createdAt,
  });

  final String publicId;
  final String status;
  final bool isActive;
  final String? pickup;
  final String? dropoff;
  final double? distanceKm;
  final int? durationMinutes;
  final double? totalFare;
  final String? currency;
  final String? customerName;
  final int? myRating;
  final DateTime? completedAt;
  final DateTime? createdAt;

  static DriverRideHistoryItem fromJson(Map<String, dynamic> j) => DriverRideHistoryItem(
        publicId: (j['public_id'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
        isActive: j['is_active'] == true,
        pickup: j['pickup_address'] as String?,
        dropoff: j['dropoff_address'] as String?,
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
        totalFare: (j['total_fare'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        customerName: j['customer_name'] as String?,
        myRating: (j['my_rating'] as num?)?.toInt(),
        completedAt: j['completed_at'] is String ? DateTime.tryParse(j['completed_at'] as String) : null,
        createdAt: j['created_at'] is String ? DateTime.tryParse(j['created_at'] as String) : null,
      );
}

/// Sürücünün kendi değerlendirmeleri.
class DriverReviews {
  const DriverReviews({required this.average, required this.count, required this.reviews});
  final double average;
  final int count;
  final List<DriverReview> reviews;
}

class DriverReview {
  const DriverReview({required this.stars, this.review, this.completedAt, this.pickup, this.dropoff});
  final int stars;
  final String? review;
  final DateTime? completedAt;
  final String? pickup;
  final String? dropoff;

  static DriverReview fromJson(Map<String, dynamic> json) => DriverReview(
        stars: (json['stars'] as num?)?.toInt() ?? 0,
        review: json['review'] as String?,
        completedAt: json['completed_at'] is String ? DateTime.tryParse(json['completed_at'] as String) : null,
        pickup: json['pickup'] as String?,
        dropoff: json['dropoff'] as String?,
      );
}
