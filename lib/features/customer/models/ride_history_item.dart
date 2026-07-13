import 'package:flutter/foundation.dart';

import '../../../core/util/json_num.dart';

@immutable
class RideHistoryItem {
  const RideHistoryItem({
    required this.publicId,
    required this.status,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMinutes,
    required this.totalFare,
    required this.currency,
    required this.driverName,
    required this.vehicleClass,
    required this.createdAt,
    required this.completedAt,
  });

  final String publicId;
  final String status;
  final String pickupAddress;
  final String dropoffAddress;
  final double distanceKm;
  final int durationMinutes;
  final double? totalFare;
  final String? currency;
  final String? driverName;
  final String? vehicleClass;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isNoShow    => status == 'no_show';

  /// Ham statü kodunu (driver_arriving, in_progress vb.) Türkçe etikete çevirir.
  String get statusLabel {
    switch (status) {
      case 'completed':        return 'Tamamlandı';
      case 'cancelled':        return 'İptal edildi';
      case 'no_show':          return 'Gelinmedi';
      case 'in_progress':      return 'Devam ediyor';
      case 'driver_arriving':  return 'Sürücü yolda';
      case 'assigned':         return 'Sürücü atandı';
      case 'searching':        return 'Sürücü aranıyor';
      case 'pending':          return 'Bekliyor';
      case 'draft':            return 'Taslak';
      case 'reservation_pending_pool':
      case 'reservation_accepted':
      case 'reservation_reconfirm_requested':
      case 'reservation_confirmed':
      case 'reservation_imminent':
        return 'Rezervasyon';
      case 'reservation_unmatched':
        return 'Eşleşme bulunamadı';
      default:                 return 'Yolculuk';
    }
  }

  static RideHistoryItem fromJson(Map<String, dynamic> json) {
    return RideHistoryItem(
      publicId: json['public_id'] as String,
      status: json['status'] as String? ?? 'pending',
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropoffAddress: json['dropoff_address'] as String? ?? '',
      distanceKm: asDoubleOr(json['distance_km'], 0),
      durationMinutes: asIntOr(json['duration_minutes'], 0),
      totalFare: asDoubleOrNull(json['total_fare']),
      currency: json['currency'] as String?,
      driverName: json['driver_name'] as String?,
      vehicleClass: json['vehicle_class'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );
  }
}
