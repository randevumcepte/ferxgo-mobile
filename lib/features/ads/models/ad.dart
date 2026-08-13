import 'package:flutter/foundation.dart';

import '../../../core/util/json_num.dart';

/// Backend `/ads` (Marketing modülü) response item'i.
///
/// Web'deki `partials/ad-slot.blade.php` ile aynı içerik: bir slot (placement) için
/// seçilen aktif reklam. [imageOnly] true ise görsel tüm alanı kaplar; aksi halde
/// görsel + başlık/açıklama + CTA butonu (split) düzeni gösterilir.
@immutable
class Ad {
  const Ad({
    required this.id,
    required this.placement,
    required this.imageOnly,
    this.sector,
    this.title,
    this.sponsorName,
    this.description,
    this.imageUrl,
    this.linkUrl,
    this.ctaText,
  });

  final int id;
  final String placement;
  final bool imageOnly;
  final String? sector;
  final String? title;
  final String? sponsorName;
  final String? description;

  /// Her zaman tam URL (backend `image_src` accessor'ı ile üretilir).
  final String? imageUrl;
  final String? linkUrl;
  final String? ctaText;

  bool get hasImage => (imageUrl ?? '').isNotEmpty;
  bool get hasLink => (linkUrl ?? '').isNotEmpty;

  static Ad fromJson(Map<String, dynamic> json) {
    return Ad(
      id: asIntOr(json['id'], 0),
      placement: (json['placement'] as String?) ?? '',
      imageOnly: (json['image_only'] as bool?) ?? false,
      sector: json['sector'] as String?,
      title: json['title'] as String?,
      sponsorName: json['sponsor_name'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      linkUrl: json['link_url'] as String?,
      ctaText: json['cta_text'] as String?,
    );
  }
}
