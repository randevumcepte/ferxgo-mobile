import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../customer_ride_repository.dart';
import '../models/ride_history_item.dart';

/// Tamamlanan/iptal olan bir yolculuğun detay ekranı.
/// Güzergâh + ücret özeti + (varsa) sürücüyü favoriye ekle/çıkar.
class RideDetailScreen extends ConsumerStatefulWidget {
  const RideDetailScreen({super.key, required this.item});

  final RideHistoryItem item;

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  static const Color _pink = Color(0xFFFB7185);

  late bool _fav = widget.item.driverIsFavorite;
  bool _favBusy = false;

  RideHistoryItem get item => widget.item;

  Color get _statusColor {
    if (item.isCompleted) return FerxgoColors.success;
    if (item.isCancelled) return FerxgoColors.danger;
    if (item.isNoShow) return FerxgoColors.warning;
    return FerxgoColors.info;
  }

  Future<void> _toggleFav() async {
    final id = item.driverId;
    if (id == null || _favBusy) return;
    final next = !_fav;
    setState(() {
      _fav = next; // iyimser
      _favBusy = true;
    });
    try {
      if (next) {
        await ref.read(customerRideRepositoryProvider).addFavorite(id);
      } else {
        await ref.read(customerRideRepositoryProvider).removeFavorite(id);
      }
      if (mounted) setState(() => _favBusy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fav = !next; // geri al
        _favBusy = false;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('İşlem yapılamadı, tekrar dene.',
              style: TextStyle(color: Colors.white)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FerxgoColors.inkMuted,
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy · HH:mm', 'tr_TR');
    final dt = item.completedAt ?? item.createdAt;

    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(
        backgroundColor: FerxgoColors.ink,
        title: const Text('Yolculuk Detayı'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // Durum + tarih
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.statusLabel.toUpperCase(),
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6),
                  ),
                ),
                const Spacer(),
                Text(df.format(dt.toLocal()),
                    style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),

            // Güzergâh
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AddrRow(icon: Icons.circle_outlined, text: item.pickupAddress, color: FerxgoColors.brand),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: SizedBox(
                      height: 18,
                      child: VerticalDivider(color: FerxgoColors.line, width: 2, thickness: 1),
                    ),
                  ),
                  _AddrRow(icon: Icons.place, text: item.dropoffAddress, color: FerxgoColors.danger),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Özet: mesafe / süre / ücret
            _Card(
              child: Row(
                children: [
                  _Metric(label: 'Mesafe', value: '${item.distanceKm.toStringAsFixed(1)} km'),
                  _divider(),
                  _Metric(label: 'Süre', value: '${item.durationMinutes} dk'),
                  _divider(),
                  _Metric(
                    label: 'Ücret',
                    value: item.totalFare != null ? '${item.totalFare!.toStringAsFixed(0)} ₺' : '—',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Sürücü + favori toggle
            if (item.driverName != null)
              _Card(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: FerxgoColors.brand.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(_initials(item.driverName!),
                          style: const TextStyle(color: FerxgoColors.brand, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sürücü',
                              style: TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(item.driverName!,
                              style: const TextStyle(
                                  color: FerxgoColors.textHigh,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (item.driverId != null)
                      _favButton()
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _favButton() {
    return OutlinedButton.icon(
      onPressed: _favBusy ? null : _toggleFav,
      style: OutlinedButton.styleFrom(
        foregroundColor: _fav ? _pink : FerxgoColors.textMid,
        side: BorderSide(color: _fav ? _pink : FerxgoColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: _favBusy
          ? const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _pink))
          : Icon(_fav ? Icons.favorite : Icons.favorite_border, size: 18),
      label: Text(_fav ? 'Favoride' : 'Favoriye ekle',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: FerxgoColors.line,
      );

  String _initials(String s) => s.isEmpty
      ? '?'
      : s.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0]).join().toUpperCase();
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: child,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
        ],
      ),
    );
  }
}

class _AddrRow extends StatelessWidget {
  const _AddrRow({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 13.5, height: 1.35)),
        ),
      ],
    );
  }
}
