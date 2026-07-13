import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Koordinatı kesinleşmiş yer — booking draft'ta pickup/dropoff olarak taşınır.
@immutable
class Place {
  const Place({required this.position, required this.displayName});

  final LatLng position;
  final String displayName;
}

/// Yer arama (autocomplete) önerisi — GeoService sözleşmesi.
///
/// Öğe şekli: { display_name, lat|null, lon|null, uri|null, provider }.
///  - Yandex önerileri koordinatsız gelir ([position] null, [uri] dolu) →
///    seçilince /customer/places/resolve ile koordinat alınır.
///  - Photon/Nominatim önerileri koordinatı zaten taşır ([position] dolu).
@immutable
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.displayName,
    this.position,
    this.uri,
    this.provider,
  });

  final String displayName;
  final LatLng? position;
  final String? uri;
  final String? provider;

  /// Koordinat yok → seçilince resolve gerekir (Yandex önerisi).
  bool get needsResolve => position == null;

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

  static PlaceSuggestion fromJson(Map<String, dynamic> json) {
    final lat = json['lat'] as num?;
    final lon = json['lon'] as num?;
    final pos = (lat != null && lon != null)
        ? LatLng(lat.toDouble(), lon.toDouble())
        : null;
    final uri = json['uri'] as String?;
    return PlaceSuggestion(
      displayName: json['display_name'] as String? ?? '',
      position: pos,
      uri: (uri != null && uri.isNotEmpty) ? uri : null,
      provider: json['provider'] as String?,
    );
  }
}
