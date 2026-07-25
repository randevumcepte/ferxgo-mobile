import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../driver_repository.dart';

final _driverHistoryProvider = FutureProvider.autoDispose<DriverHistory>((ref) {
  return ref.watch(driverRepositoryProvider).history(limit: 50);
});

/// Sürücünün yaptığı yolculuklar — tamamlanan + iptal, en yenisi üstte.
class DriverHistoryScreen extends ConsumerWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_driverHistoryProvider);

    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(title: const Text('Yolculuklarım')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: FerxgoColors.brand)),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Yolculuklar yüklenemedi.\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: FerxgoColors.textMid)),
            ),
          ),
          data: (data) => RefreshIndicator(
            color: FerxgoColors.brand,
            onRefresh: () async => ref.refresh(_driverHistoryProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Özet: toplam tamamlanan yolculuk
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [FerxgoColors.brand.withValues(alpha: 0.18), FerxgoColors.inkSoft],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Text('${data.completedTotal}',
                        style: const TextStyle(color: FerxgoColors.brand, fontSize: 40, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text('Tamamlanan yolculuk',
                          style: TextStyle(color: FerxgoColors.textMid, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      const Icon(Icons.receipt_long_outlined, color: FerxgoColors.brand, size: 28),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (data.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text('Henüz yolculuk yok.\nTamamladığın yolculuklar burada listelenecek.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: FerxgoColors.textLow, height: 1.5)),
                    ),
                  )
                else
                  ...data.items.map((r) => _RideCard(ride: r)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride});
  final DriverRideHistoryItem ride;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy · HH:mm', 'tr_TR');
    final date = ride.completedAt ?? ride.createdAt;
    final (statusLabel, statusColor) = _statusStyle(ride.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FerxgoColors.inkSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FerxgoColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üst satır: durum rozeti + tarih
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (date != null)
                Text(df.format(date.toLocal()),
                  style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),

          // Güzergah
          _RouteRow(icon: Icons.trip_origin, color: FerxgoColors.success, text: ride.pickup ?? '—'),
          const Padding(
            padding: EdgeInsets.only(left: 7, top: 2, bottom: 2),
            child: SizedBox(height: 10, child: VerticalDivider(color: FerxgoColors.line, width: 1, thickness: 1)),
          ),
          _RouteRow(icon: Icons.place, color: FerxgoColors.danger, text: ride.dropoff ?? '—'),

          const SizedBox(height: 10),
          const Divider(color: FerxgoColors.line, height: 1),
          const SizedBox(height: 10),

          // Alt satır: yolcu + mesafe/süre + ücret
          Row(
            children: [
              const Icon(Icons.person_outline, color: FerxgoColors.textLow, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(ride.customerName ?? 'Yolcu',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
              ),
              if (ride.myRating != null) ...[
                const Icon(Icons.star_rounded, color: FerxgoColors.brand, size: 15),
                const SizedBox(width: 2),
                Text('${ride.myRating}',
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 12)),
                const SizedBox(width: 10),
              ],
              if (ride.totalFare != null)
                Text('${ride.totalFare!.toStringAsFixed(0)} ${ride.currency ?? '₺'}',
                  style: const TextStyle(color: FerxgoColors.brand, fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          if (ride.distanceKm != null || ride.durationMinutes != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (ride.distanceKm != null) '${ride.distanceKm!.toStringAsFixed(1)} km',
                if (ride.durationMinutes != null) '${ride.durationMinutes} dk',
              ].join(' · '),
              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  (String, Color) _statusStyle(String status) {
    switch (status) {
      case 'completed':
        return ('Tamamlandı', FerxgoColors.success);
      case 'cancelled':
        return ('İptal edildi', FerxgoColors.danger);
      case 'no_show':
        return ('Gelmedi', FerxgoColors.warning);
      case 'in_progress':
      case 'started':
        return ('Devam ediyor', FerxgoColors.brand);
      default:
        return ('Aktif', FerxgoColors.info);
    }
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 13)),
        ),
      ],
    );
  }
}
