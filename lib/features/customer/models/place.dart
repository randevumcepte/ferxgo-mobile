import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Nominatim search-places sonucu.
@immutable
class Place {
  const Place({required this.position, required this.displayName});

  final LatLng position;
  final String displayName;

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

  static Place fromJson(Map<String, dynamic> json) => Place(
        position: LatLng(
          ((json['lat'] as num?) ?? 0).toDouble(),
          ((json['lon'] as num?) ?? 0).toDouble(),
        ),
        displayName: json['display_name'] as String? ?? '',
      );
}
