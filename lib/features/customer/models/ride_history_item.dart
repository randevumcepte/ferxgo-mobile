import 'package:flutter/foundation.dart';

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

  static RideHistoryItem fromJson(Map<String, dynamic> json) {
    return RideHistoryItem(
      publicId: json['public_id'] as String,
      status: json['status'] as String? ?? 'pending',
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropoffAddress: json['dropoff_address'] as String? ?? '',
      distanceKm: ((json['distance_km'] as num?) ?? 0).toDouble(),
      durationMinutes: ((json['duration_minutes'] as num?) ?? 0).toInt(),
      totalFare: (json['total_fare'] as num?)?.toDouble(),
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
