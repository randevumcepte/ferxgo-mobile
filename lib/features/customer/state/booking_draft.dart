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

  /// Reddedilince/iptal olunca dolu onay ekranına geri dönmek için draft'ı geri yükle.
  void restore({
    required Place pickup,
    required Place dropoff,
    required double distanceKm,
    required int durationMinutes,
    double? fare,
  }) {
    state = BookingDraft(
      pickup: pickup,
      dropoff: dropoff,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
      estimatedFare: fare,
    );
  }
}

final bookingDraftProvider = NotifierProvider<BookingDraftController, BookingDraft>(
  BookingDraftController.new,
);

/// Son gönderilen talebin özeti — 1:1 reddedilince/süre dolunca tracking'de
/// "Tüm favorilerime gönder" için rota/teklif bilgisini taşır.
@immutable
class DispatchSnapshot {
  const DispatchSnapshot({
    required this.vehicleClassSlug,
    required this.pickupAddress,
    required this.pickupPosition,
    required this.dropoffAddress,
    required this.dropoffPosition,
    required this.distanceKm,
    required this.durationMinutes,
    this.estimatedFare,
    this.offerFare,
    this.stage = 'one',
    this.favoriteCount = 0,
  });

  /// Son dağıtım aşaması: 'one' (tek favoriye 1:1) | 'all' (tüm favoriler) | 'nearby'.
  /// Reddedilince tracking bir sonraki kademeyi teklif eder.
  final String stage;

  /// Yolcunun toplam favori sayısı — 1:1 reddinde "tüm favorilere" adımı gösterilsin mi.
  final int favoriteCount;

  final String vehicleClassSlug;
  final String pickupAddress;
  final LatLng pickupPosition;
  final String dropoffAddress;
  final LatLng dropoffPosition;
  final double distanceKm;
  final int durationMinutes;
  final double? estimatedFare;
  final double? offerFare;
}

final lastDispatchProvider = StateProvider<DispatchSnapshot?>((ref) => null);

/// Bootstrap'tan gelen vehicle class'lar — cache'lensin.
final vehicleClassesProvider = FutureProvider<List<VehicleClassRef>>((ref) async {
  return ref.watch(customerRideRepositoryProvider).vehicleClasses();
});
