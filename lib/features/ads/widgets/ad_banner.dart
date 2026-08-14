import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../ad_repository.dart';
import '../models/ad.dart';

/// Bir reklam slotunu (placement) kendi kendine besleyen kart.
///
/// initState'te backend'den slotun aktif reklamını çeker (gösterim otomatik
/// kaydedilir). Reklam yoksa hiç yer kaplamaz (boş görünmez). Tıklanınca tıklama
/// kaydedilir ve reklamın hedef linki harici tarayıcıda açılır.
///
/// Web'deki `partials/ad-slot.blade.php` karşılığı: image_only ise görsel tüm
/// alanı kaplar, aksi halde görsel + başlık/açıklama + CTA (split) düzeni.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({
    super.key,
    required this.placement,
    this.lat,
    this.lng,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final String placement;
  final double? lat;
  final double? lng;
  final EdgeInsets margin;

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  Ad? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdBanner old) {
    super.didUpdateWidget(old);
    // Konum sonradan çözülünce (varsayılan merkez → gerçek konum) veya kullanıcı
    // belirgin şekilde yer değiştirince reklamı konuma göre yeniden çek.
    if (_coordsChanged(old.lat, old.lng, widget.lat, widget.lng)) {
      _load();
    }
  }

  /// null↔değer geçişi (ilk konum kilidi) veya ~500m'den fazla kayma → yeniden çek.
  /// Eşik, GPS titremesinde gereksiz tekrar isteğini (ve gösterim sayacı şişmesini) engeller.
  bool _coordsChanged(double? oldLat, double? oldLng, double? newLat, double? newLng) {
    final hadCoords = oldLat != null && oldLng != null;
    final hasCoords = newLat != null && newLng != null;
    if (hadCoords != hasCoords) return true;
    if (!hasCoords) return false;
    const threshold = 0.005; // ~500m
    return (oldLat! - newLat).abs() > threshold || (oldLng! - newLng).abs() > threshold;
  }

  Future<void> _load() async {
    try {
      final ad = await ref.read(adRepositoryProvider).fetchOne(
            widget.placement,
            lat: widget.lat,
            lng: widget.lng,
          );
      if (!mounted) return;
      setState(() {
        _ad = ad;
        _loaded = true;
      });
    } catch (_) {
      // Reklam kritik değil — hata olursa sessizce boş bırak.
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  Future<void> _onTap(Ad ad) async {
    if (!ad.hasLink) return;
    String? target = ad.linkUrl;
    try {
      final link = await ref.read(adRepositoryProvider).registerClick(
            ad.id,
            lat: widget.lat,
            lng: widget.lng,
          );
      if (link != null && link.isNotEmpty) target = link;
    } catch (_) {
      // Tıklama kaydı başarısız olsa da linki yine de açmayı dene.
    }
    if (target == null || target.isEmpty) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();

    return Padding(
      padding: widget.margin,
      child: Material(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: ad.hasLink ? () => _onTap(ad) : null,
          child: ad.imageOnly && ad.hasImage
              ? _imageOnly(ad)
              : _split(ad),
        ),
      ),
    );
  }

  /// Tam görsel modu — görsel tüm alanı kaplar (önerilen 3:1).
  Widget _imageOnly(Ad ad) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 3 / 1,
          child: _image(ad.imageUrl!),
        ),
        const Positioned(top: 8, right: 8, child: _AdLabel()),
      ],
    );
  }

  /// Split mod — görsel + başlık/açıklama + CTA.
  Widget _split(Ad ad) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: FerxgoColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ad.hasImage)
            AspectRatio(
              aspectRatio: 3 / 1,
              child: _image(ad.imageUrl!),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if ((ad.sponsorName ?? '').isNotEmpty)
                      Expanded(
                        child: Text(
                          ad.sponsorName!,
                          style: const TextStyle(
                            color: FerxgoColors.textLow,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const _AdLabel(),
                  ],
                ),
                if ((ad.title ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    ad.title!,
                    style: const TextStyle(
                      color: FerxgoColors.textHigh,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
                if ((ad.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    ad.description!,
                    style: const TextStyle(
                      color: FerxgoColors.textMid,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                if (ad.hasLink) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: FerxgoColors.brand,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        (ad.ctaText ?? '').isNotEmpty ? ad.ctaText! : 'İncele',
                        style: const TextStyle(
                          color: FerxgoColors.textInkHigh,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _image(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: FerxgoColors.inkMuted,
          child: const Center(
            child: SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: FerxgoColors.textLow),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) => Container(
        color: FerxgoColors.inkMuted,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined,
            color: FerxgoColors.textLow, size: 28),
      ),
    );
  }
}

/// "Reklam" şeffaflık etiketi (mağaza politikaları + kullanıcı güveni).
class _AdLabel extends StatelessWidget {
  const _AdLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'REKLAM',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
