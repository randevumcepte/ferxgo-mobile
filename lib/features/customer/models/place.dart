import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Yer arama (GeoService: Yandex/Photon/Nominatim) sonucu.
/// Yandex önerileri KOORDİNATSIZ gelir (uri dolu) → seçilince /places/resolve
/// ile koordinat alınır. [hasCoords] false ise position (0,0) placeholder'dır.
@immutable
class Place {
  const Place({
    required this.position,
    required this.displayName,
    this.uri,
    this.hasCoords = true,
  });

  final LatLng position;
  final String displayName;
  final String? uri;
  final bool hasCoords;

  /// İlk virgüle kadar olan kısa ad (UI'da başlık).
  String get shortName {
    final i = displayName.indexOf(',');
    return i > 0 ? displayName.substring(0, i) : displayName;
  }

  /// "Kısa ad" sonrası kalan kısım (UI'da gri alt yazı).
  String get secondaryName {
    final i = displayName.indexOf(',');
    return i > 0 ? displayName.substring(i + 1).trim() : '';
  }

  static Place fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    final has = lat != null && lon != null;
    return Place(
      position: has ? LatLng(lat, lon) : const LatLng(0, 0),
      displayName: json['display_name'] as String? ?? '',
      uri: json['uri'] as String?,
      hasCoords: has,
    );
  }
}
