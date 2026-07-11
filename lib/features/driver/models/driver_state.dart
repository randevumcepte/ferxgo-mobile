import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/models/negotiation.dart';
import '../../customer/models/ride_status.dart' show RideMessage;

/// `/driver/state` tek-endpoint polling yanıtının parse hali.
/// driver + offer + active + messages hepsi burada.
@immutable
class DriverState {
  const DriverState({
    required this.driver,
    required this.offer,
    required this.active,
    required this.messages,
  });

  final DriverInfo driver;
  final DriverOffer? offer;
  final DriverActive? active;
  final List<RideMessage> messages;

  bool get isOnline => driver.availabilityStatus == 'online';
  bool get isBusy => driver.availabilityStatus == 'busy';
  bool get hasOffer => offer != null;
  bool get hasActive => active != null;

  static DriverState fromJson(Map<String, dynamic> json) {
    final msgs = (json['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => RideMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
    return DriverState(
      driver: DriverInfo.fromJson((json['driver'] as Map).cast<String, dynamic>()),
      offer: json['offer'] is Map
          ? DriverOffer.fromJson((json['offer'] as Map).cast<String, dynamic>())
          : null,
      active: json['active'] is Map
          ? DriverActive.fromJson((json['active'] as Map).cast<String, dynamic>())
          : null,
      messages: msgs,
    );
  }
}

@immutable
class DriverInfo {
  const DriverInfo({
    required this.id,
    required this.name,
    required this.availabilityStatus,
    required this.rating,
    required this.totalRides,
    required this.isFemale,
    required this.womenOnly,
  });

  final int id;
  final String name;
  final String availabilityStatus; // online | offline | busy
  final double rating;
  final int totalRides;
  final bool isFemale;
  final bool womenOnly;

  static DriverInfo fromJson(Map<String, dynamic> json) => DriverInfo(
        id: (json['id'] as num).toInt(),
        name: (json['name'] as String?) ?? 'Sürücü',
        availabilityStatus: (json['availability_status'] as String?) ?? 'offline',
        rating: ((json['rating'] as num?) ?? 0).toDouble(),
        totalRides: ((json['total_rides'] as num?) ?? 0).toInt(),
        isFemale: (json['is_female'] as bool?) ?? false,
        womenOnly: (json['women_only'] as bool?) ?? false,
      );
}

/// Gelen teklif — 35 sn sayaç + yolcu teklifi (pazarlık).
@immutable
class DriverOffer {
  const DriverOffer({
    required this.publicId,
    required this.customerName,
    required this.pickupAddress,
    required this.pickupPosition,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedFare,
    required this.secondsRemaining,
    required this.negotiation,
  });

  final String publicId;
  final String customerName;
  final String pickupAddress;
  final LatLng pickupPosition;
  final String dropoffAddress;
  final double distanceKm;
  final int durationMinutes;
  final double? estimatedFare;
  final int secondsRemaining;
  final Negotiation? negotiation;

  /// Yolcunun teklif ettiği ücret (kabul edilecek tutar). Yoksa tahmini/öneri.
  double get customerOffer =>
      negotiation?.customerOfferFare ?? estimatedFare ?? 0;

  static DriverOffer fromJson(Map<String, dynamic> json) => DriverOffer(
        publicId: json['public_id'] as String,
        customerName: (json['customer_name'] as String?) ?? 'Müşteri',
        pickupAddress: (json['pickup_address'] as String?) ?? '',
        pickupPosition: LatLng(
          ((json['pickup_lat'] as num?) ?? 38.4377).toDouble(),
          ((json['pickup_lng'] as num?) ?? 27.1428).toDouble(),
        ),
        dropoffAddress: (json['dropoff_address'] as String?) ?? '',
        distanceKm: ((json['distance_km'] as num?) ?? 0).toDouble(),
        durationMinutes: ((json['duration_minutes'] as num?) ?? 0).toInt(),
        estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
        secondsRemaining: ((json['seconds_remaining'] as num?) ?? 0).toInt(),
        negotiation: Negotiation.fromJson(json['negotiation']),
      );
}

/// Aktif yolculuk — vardım/no-show/tamamla + yolcu güven bilgisi.
@immutable
class DriverActive {
  const DriverActive({
    required this.publicId,
    required this.customerName,
    required this.customerPhone,
    required this.customerTrustLabel,
    required this.customerIsNew,
    required this.customerCompletedRides,
    required this.customerNoShows,
    required this.pickupAddress,
    required this.pickupPosition,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMinutes,
    required this.estimatedFare,
    required this.arrivedAt,
    required this.customerConfirmedAt,
    required this.noShowButtonReady,
    required this.noShowCountdownSec,
    required this.rideStatus,
  });

  final String publicId;
  final String customerName;
  final String? customerPhone;
  final String customerTrustLabel;
  final bool customerIsNew;
  final int customerCompletedRides;
  final int customerNoShows;
  final String pickupAddress;
  final LatLng pickupPosition;
  final String dropoffAddress;
  final double distanceKm;
  final int durationMinutes;
  final double? estimatedFare;
  final DateTime? arrivedAt;
  final DateTime? customerConfirmedAt;
  final bool noShowButtonReady;
  final int? noShowCountdownSec;
  final String? rideStatus;

  bool get arrived => arrivedAt != null;
  bool get confirmed => customerConfirmedAt != null;

  static DriverActive fromJson(Map<String, dynamic> json) {
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return DriverActive(
      publicId: json['public_id'] as String,
      customerName: (json['customer_name'] as String?) ?? 'Müşteri',
      customerPhone: json['customer_phone'] as String?,
      customerTrustLabel: (json['customer_trust_label'] as String?) ?? '',
      customerIsNew: (json['customer_is_new'] as bool?) ?? false,
      customerCompletedRides: ((json['customer_completed_rides'] as num?) ?? 0).toInt(),
      customerNoShows: ((json['customer_no_shows'] as num?) ?? 0).toInt(),
      pickupAddress: (json['pickup_address'] as String?) ?? '',
      pickupPosition: LatLng(
        ((json['pickup_lat'] as num?) ?? 38.4377).toDouble(),
        ((json['pickup_lng'] as num?) ?? 27.1428).toDouble(),
      ),
      dropoffAddress: (json['dropoff_address'] as String?) ?? '',
      distanceKm: ((json['distance_km'] as num?) ?? 0).toDouble(),
      durationMinutes: ((json['duration_minutes'] as num?) ?? 0).toInt(),
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble(),
      arrivedAt: d(json['arrived_at']),
      customerConfirmedAt: d(json['customer_confirmed_at']),
      noShowButtonReady: (json['no_show_button_ready'] as bool?) ?? false,
      noShowCountdownSec: (json['no_show_countdown_sec'] as num?)?.toInt(),
      rideStatus: json['ride_status'] as String?,
    );
  }
}
