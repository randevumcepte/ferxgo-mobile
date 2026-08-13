import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../ad_repository.dart';
import '../models/ad.dart';

/// Açılır pencere (popup) reklamı — web'deki `partials/ad-popup.blade.php` karşılığı.
///
/// Ana ekran açıldığında [maybeShow] çağrılır; `popup` slotunda aktif reklam varsa
/// bir kez (oturum başına) modal olarak gösterilir. Reklam yoksa hiçbir şey olmaz.
class AdPopup {
  AdPopup._();

  /// Rahatsız etmemek için oturum başına tek gösterim.
  static bool _shownThisSession = false;

  static Future<void> maybeShow(
    BuildContext context,
    WidgetRef ref, {
    double? lat,
    double? lng,
  }) async {
    if (_shownThisSession) return;
    _shownThisSession = true;

    Ad? ad;
    try {
      ad = await ref.read(adRepositoryProvider).fetchOne(
            AdPlacements.popup,
            lat: lat,
            lng: lng,
          );
    } catch (_) {
      return;
    }
    if (ad == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => _AdPopupDialog(ad: ad!, lat: lat, lng: lng),
    );
  }
}

class _AdPopupDialog extends ConsumerWidget {
  const _AdPopupDialog({required this.ad, this.lat, this.lng});

  final Ad ad;
  final double? lat;
  final double? lng;

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    String? target = ad.linkUrl;
    try {
      final link = await ref.read(adRepositoryProvider).registerClick(ad.id, lat: lat, lng: lng);
      if (link != null && link.isNotEmpty) target = link;
    } catch (_) {}
    if (context.mounted) Navigator.of(context).maybePop();
    if (target == null || target.isEmpty) return;
    final uri = Uri.tryParse(target);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: FerxgoColors.inkSoft,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              if (ad.hasImage)
                InkWell(
                  onTap: ad.hasLink ? () => _onTap(context, ref) : null,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      ad.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        color: FerxgoColors.inkMuted,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image_not_supported_outlined,
                            color: FerxgoColors.textLow, size: 36),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 8, right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
              const Positioned(top: 8, left: 8, child: _PopupAdLabel()),
            ],
          ),
          if (!ad.imageOnly && ((ad.title ?? '').isNotEmpty || (ad.description ?? '').isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((ad.title ?? '').isNotEmpty)
                    Text(ad.title!,
                        style: const TextStyle(
                            color: FerxgoColors.textHigh,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                  if ((ad.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(ad.description!,
                        style: const TextStyle(
                            color: FerxgoColors.textMid, fontSize: 14, height: 1.4)),
                  ],
                ],
              ),
            ),
          if (ad.hasLink)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: FerxgoColors.brand,
                    foregroundColor: FerxgoColors.textInkHigh,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _onTap(context, ref),
                  child: Text(
                    (ad.ctaText ?? '').isNotEmpty ? ad.ctaText! : 'İncele',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PopupAdLabel extends StatelessWidget {
  const _PopupAdLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('REKLAM',
          style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6)),
    );
  }
}
