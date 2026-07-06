import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Konum izni + son konum okuma. UI tarafı durum kodlarına göre rehberlik gösterir.
class LocationService {
  /// İzmir Alsancak — izin yoksa veya konum alınamazsa harita merkezi.
  static const LatLng defaultCenter = LatLng(38.4377, 27.1428);

  /// Mevcut izni kontrol et + gerekirse iste. Sonra son konumu döndür.
  ///
  /// Sonuç:
  ///  - LocationFix(lat, lng) — başarılı
  ///  - LocationError(reason) — servis kapalı / izin reddedildi / kalıcı engelli
  Future<LocationResult> currentPosition({Duration timeout = const Duration(seconds: 8)}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationError(LocationFailReason.serviceOff);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationError(LocationFailReason.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationError(LocationFailReason.deniedForever);
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(timeout);
      return LocationFix(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // Fallback: son bilinen konum (eski ama hızlı)
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LocationFix(LatLng(last.latitude, last.longitude));
      }
      return const LocationError(LocationFailReason.timeout);
    }
  }
}

sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix(this.position);
  final LatLng position;
}

class LocationError extends LocationResult {
  const LocationError(this.reason);
  final LocationFailReason reason;
}

enum LocationFailReason { serviceOff, denied, deniedForever, timeout }

extension LocationFailReasonX on LocationFailReason {
  String get userMessage => switch (this) {
        LocationFailReason.serviceOff =>
          'Telefonun konum servisi kapalı. Ayarlardan açıp tekrar dene.',
        LocationFailReason.denied =>
          'Konum izni vermediğin için yakındaki sürücüleri gösteremedik.',
        LocationFailReason.deniedForever =>
          'Konum izni kalıcı reddedilmiş. Ayarlar > Uygulamalar > FerXGo bölümünden izin ver.',
        LocationFailReason.timeout =>
          'Konum alınamadı, ağ ve GPS sinyalini kontrol et.',
      };
}

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
