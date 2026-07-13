import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/location/location_service.dart';
import '../../core/theme/app_colors.dart';

/// FerXGo çağrı merkezi (web paniğiyle aynı numara).
const String kPanicCallCenter = '+908503403039';

/// Acil yardım (panik) API katmanı — mobil /panic (Sanctum bearer).
class PanicRepository {
  PanicRepository(this._api);
  final ApiClient _api;

  /// Güvenlik ekibine alarm gönderir (+ opsiyonel konum). Dönen: alert bilgisi.
  Future<Map<String, dynamic>> trigger({String? ridePublicId, double? lat, double? lng}) async {
    return _api.postJson('/panic', body: {
      'ride_request_public_id': ?ridePublicId,
      'lat': ?lat,
      'lng': ?lng,
    });
  }
}

final panicRepositoryProvider = Provider<PanicRepository>((ref) {
  return PanicRepository(ref.watch(apiClientProvider));
});

/// Yolculuk sırasında ekranda duran kırmızı 🚨 acil yardım butonu.
/// Basınca aksiyon menüsü açılır: güvenlik ekibine alarm+konum, çağrı merkezi, paylaş.
class PanicButton extends ConsumerWidget {
  const PanicButton({
    super.key,
    this.ridePublicId,
    required this.shareDescription,
  });

  /// Aktif yolculuk public id (alarmı yolculukla ilişkilendirir).
  final String? ridePublicId;

  /// "Yolculuğu paylaş" için hazır metin (sürücü/plaka/güzergah). Konum otomatik eklenir.
  final String shareDescription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSheet(context, ref),
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: FerxgoColors.danger,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: [
              BoxShadow(color: FerxgoColors.danger.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1),
            ],
          ),
          alignment: Alignment.center,
          child: const Text('🚨', style: TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FerxgoColors.inkSoft,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PanicSheet(ridePublicId: ridePublicId, shareDescription: shareDescription),
    );
  }
}

class _PanicSheet extends ConsumerStatefulWidget {
  const _PanicSheet({required this.ridePublicId, required this.shareDescription});
  final String? ridePublicId;
  final String shareDescription;

  @override
  ConsumerState<_PanicSheet> createState() => _PanicSheetState();
}

class _PanicSheetState extends ConsumerState<_PanicSheet> {
  bool _sendingAlert = false;
  bool _alertSent = false;

  Future<({double? lat, double? lng})> _currentLatLng() async {
    try {
      final loc = await ref.read(locationServiceProvider).currentPosition();
      if (loc is LocationFix) {
        return (lat: loc.position.latitude, lng: loc.position.longitude);
      }
    } catch (_) {}
    return (lat: null, lng: null);
  }

  Future<void> _sendAlert() async {
    setState(() => _sendingAlert = true);
    final pos = await _currentLatLng();
    try {
      await ref.read(panicRepositoryProvider).trigger(
            ridePublicId: widget.ridePublicId,
            lat: pos.lat,
            lng: pos.lng,
          );
      if (!mounted) return;
      setState(() => _alertSent = true);
      _snack('Acil yardım talebin alındı. Çağrı merkezi seni birazdan arayacak.', FerxgoColors.success);
    } catch (_) {
      if (!mounted) return;
      _snack('Alarm gönderilemedi. Lütfen çağrı merkezini ara.', FerxgoColors.danger);
    } finally {
      if (mounted) setState(() => _sendingAlert = false);
    }
  }

  Future<void> _callCenter() async {
    final uri = Uri.parse('tel:$kPanicCallCenter');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _shareRide() async {
    final pos = await _currentLatLng();
    final buf = StringBuffer('🚨 FerXGo yolculuğumdayım.\n')..write(widget.shareDescription);
    if (pos.lat != null && pos.lng != null) {
      buf.write('\nKonumum: https://maps.google.com/?q=${pos.lat},${pos.lng}');
    }
    await Share.share(buf.toString());
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: FerxgoColors.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: const [
              Text('🚨', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Text('Acil Yardım',
                style: TextStyle(color: FerxgoColors.textHigh, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Kendini güvende hissetmiyorsan aşağıdan yardım al.',
            style: TextStyle(color: FerxgoColors.textMid, fontSize: 13, height: 1.4)),
          const SizedBox(height: 18),

          // 1) Güvenlik ekibine alarm + konum
          _PanicAction(
            icon: _alertSent ? Icons.check_circle : Icons.shield,
            iconColor: _alertSent ? FerxgoColors.success : FerxgoColors.danger,
            title: _alertSent ? 'Alarm gönderildi' : 'Güvenlik ekibine bildir',
            subtitle: _alertSent
                ? 'Çağrı merkezi seni arayacak.'
                : 'Konumunla birlikte anlık alarm gönderilir.',
            busy: _sendingAlert,
            onTap: _alertSent || _sendingAlert ? null : _sendAlert,
            emphasize: true,
          ),
          const SizedBox(height: 10),

          // 2) Çağrı merkezini ara
          _PanicAction(
            icon: Icons.call,
            iconColor: FerxgoColors.success,
            title: 'Çağrı merkezini ara',
            subtitle: kPanicCallCenter,
            onTap: _callCenter,
          ),
          const SizedBox(height: 10),

          // 3) Yolculuğu paylaş
          _PanicAction(
            icon: Icons.ios_share,
            iconColor: FerxgoColors.info,
            title: 'Yolculuğu paylaş',
            subtitle: 'Sürücü ve konum bilgini bir yakınına gönder.',
            onTap: _shareRide,
          ),
          const SizedBox(height: 14),

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat', style: TextStyle(color: FerxgoColors.textMid)),
          ),
        ],
      ),
    );
  }
}

class _PanicAction extends StatelessWidget {
  const _PanicAction({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
    this.emphasize = false,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasize ? FerxgoColors.danger.withValues(alpha: 0.10) : FerxgoColors.ink,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: emphasize ? FerxgoColors.danger.withValues(alpha: 0.45) : FerxgoColors.line,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26, height: 26,
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2.4, color: FerxgoColors.danger)
                    : Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                      style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
