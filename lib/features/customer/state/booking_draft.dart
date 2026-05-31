import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../customer_ride_repository.dart';
import '../models/place.dart';
import '../models/vehicle_class.dart';

/// Müşterinin talep oluştururken biriktirdiği state.
/// Pickup haritada belirlenir (kullanıcının konumu), dropoff arama ile,
/// vehicleClass + fare onay ekranında.
@immutable
class BookingDraft {
  const BookingDraft({
    this.pickup,
    this.dropoff,
    this.vehicleClass,
    this.distanceKm,
    this.durationMinutes,
    this.estimatedFare,
  });

  final Place? pickup;
  final Place? dropoff;
  final VehicleClassRef? vehicleClass;
  final double? distanceKm;
  final int? durationMinutes;
  final double? estimatedFare;

  bool get hasRoute => pickup != null && dropoff != null;
  bool get isReadyToRequest =>
      hasRoute && vehicleClass != null && distanceKm != null && durationMinutes != null;

  BookingDraft copyWith({
    Place? pickup,
    Place? dropoff,
    VehicleClassRef? vehicleClass,
    double? distanceKm,
    int? durationMinutes,
    double? estimatedFare,
  }) =>
      BookingDraft(
        pickup: pickup ?? this.pickup,
        dropoff: dropoff ?? this.dropoff,
        vehicleClass: vehicleClass ?? this.vehicleClass,
        distanceKm: distanceKm ?? this.distanceKm,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        estimatedFare: estimatedFare ?? this.estimatedFare,
      );
}

class BookingDraftController extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => const BookingDraft();

  void setPickup(Place p) => state = state.copyWith(pickup: p);
  void setPickupFromPosition(LatLng pos, {String? label}) =>
      state = state.copyWith(pickup: Place(position: pos, displayName: label ?? 'Konumum'));
  void setDropoff(Place p) => state = state.copyWith(dropoff: p);
  void clearDropoff() => state = BookingDraft(pickup: state.pickup);
  void setVehicleClass(VehicleClassRef v) => state = state.copyWith(vehicleClass: v);
  void setRoute({required double distanceKm, required int durationMinutes, double? fare}) =>
      state = state.copyWith(
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        estimatedFare: fare,
      );
  void reset() => state = const BookingDraft();
}

final bookingDraftProvider = NotifierProvider<BookingDraftController, BookingDraft>(
  BookingDraftController.new,
);

/// Bootstrap'tan gelen vehicle class'lar — cache'lensin.
final vehicleClassesProvider = FutureProvider<List<VehicleClassRef>>((ref) async {
  return ref.watch(customerRideRepositoryProvider).vehicleClasses();
});
