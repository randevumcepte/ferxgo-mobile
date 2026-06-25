import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Backend `/customer/drivers/nearby` response item'i + bonus distance/eta.
@immutable
class NearbyDriver {
  const NearbyDriver({
    required this.id,
    required this.name,
    required this.fullName,
    required this.avatar,
    required this.rating,
    required this.trips,
    required this.vehicleClass,
    required this.vehicleClassSlug,
    required this.vehicleLabel,
    required this.vehicleYear,
    required this.vehicleColor,
    required this.plate,
    required this.distanceKm,
    required this.etaMinutes,
    required this.position,
    this.isFavorite = false,
    this.favoriteCount = 0,
    this.isFemale = false,
    this.womenOnly = false,
  });

  final int id;
  final String name;
  final String fullName;
  final String? avatar;
  final double rating;
  final int trips;
  final String? vehicleClass;
  final String? vehicleClassSlug;
  final String? vehicleLabel;
  final int? vehicleYear;
  final String? vehicleColor;
  final String? plate;
  final double distanceKm;
  final int etaMinutes;

  /// Favori / sosyal kanıt
  final bool isFavorite;
  final int favoriteCount;

  /// Kadın sürücü güvenliği
  final bool isFemale;
  final bool womenOnly;

  /// Sürücünün GPS konumu — harita marker'ı için. Nearby endpoint şu an
  /// sürücünün koordinatlarını dönmüyor (sadece distance/eta) — bu yüzden
  /// marker konumlarını backend'in eklemesi gerekecek. Şimdilik hesaplanmış
  /// "fake" konum tutuyoruz, gerçek koordinat gelene kadar.
  final LatLng position;

  static NearbyDriver fromJson(Map<String, dynamic> json, {required LatLng fallback}) {
    return NearbyDriver(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?) ?? 'Sürücü',
      fullName: (json['full_name'] as String?) ?? '',
      avatar: json['avatar'] as String?,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      trips: ((json['trips'] as num?) ?? 0).toInt(),
      vehicleClass: json['vehicle_class'] as String?,
      vehicleClassSlug: json['vehicle_class_slug'] as String?,
      vehicleLabel: json['vehicle_label'] as String?,
      vehicleYear: (json['vehicle_year'] as num?)?.toInt(),
      vehicleColor: json['vehicle_color'] as String?,
      plate: json['plate'] as String?,
      distanceKm: ((json['distance_km'] as num?) ?? 0).toDouble(),
      etaMinutes: ((json['eta_minutes'] as num?) ?? 0).toInt(),
      // Backend lat/lng dönerse o, yoksa kullanıcı konumundan offset ile yaklaşıklık
      position: _resolvePosition(json, fallback),
      isFavorite: (json['is_favorite'] as bool?) ?? false,
      favoriteCount: ((json['favorite_count'] as num?) ?? 0).toInt(),
      isFemale: (json['is_female'] as bool?) ?? false,
      womenOnly: (json['women_only'] as bool?) ?? false,
    );
  }

  NearbyDriver copyWith({bool? isFavorite, int? favoriteCount}) {
    return NearbyDriver(
      id: id,
      name: name,
      fullName: fullName,
      avatar: avatar,
      rating: rating,
      trips: trips,
      vehicleClass: vehicleClass,
      vehicleClassSlug: vehicleClassSlug,
      vehicleLabel: vehicleLabel,
      vehicleYear: vehicleYear,
      vehicleColor: vehicleColor,
      plate: plate,
      distanceKm: distanceKm,
      etaMinutes: etaMinutes,
      position: position,
      isFavorite: isFavorite ?? this.isFavorite,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      isFemale: isFemale,
      womenOnly: womenOnly,
    );
  }

  static LatLng _resolvePosition(Map<String, dynamic> json, LatLng fallback) {
    final lat = (json['current_lat'] as num?)?.toDouble();
    final lng = (json['current_lng'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return fallback;
  }
}
