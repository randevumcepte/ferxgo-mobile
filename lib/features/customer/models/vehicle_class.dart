import 'package:flutter/foundation.dart';

@immutable
class VehicleClassRef {
  const VehicleClassRef({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
  });

  final int id;
  final String slug;
  final String name;
  final String? description;

  static VehicleClassRef fromJson(Map<String, dynamic> json) => VehicleClassRef(
        id: (json['id'] as num).toInt(),
        slug: json['slug'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
      );
}
