import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/error_banner.dart';
import '../customer_ride_repository.dart';
import '../models/ride_history_item.dart';

final _historyProvider = FutureProvider.autoDispose<List<RideHistoryItem>>((ref) async {
  return ref.watch(customerRideRepositoryProvider).history(limit: 30);
});

class CustomerHistoryScreen extends ConsumerWidget {
  const CustomerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yolculuklarım'),
        backgroundColor: FerogoColors.ink,
      ),
      body: RefreshIndicator(
        color: FerogoColors.brand,
        onRefresh: () async => ref.invalidate(_historyProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: FerogoColors.brand)),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ErrorBanner(message: 'Geçmiş yüklenemedi.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(_historyProvider), child: const Text('Tekrar dene')),
            ],
          ),
          data: (rides) {
            if (rides.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 60),
                  Icon(Icons.directions_car_filled_outlined, size: 56, color: FerogoColors.textLow),
                  SizedBox(height: 16),
                  Text(
                    'Henüz yolculuk yapmamışsın',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FerogoColors.textHigh, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'İlk talebini gönderdiğinde burada görünecek.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FerogoColors.textLow),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: rides.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _RideTile(item: rides[i]),
            );
          },
        ),
      ),
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.item});
  final RideHistoryItem item;

  Color get _statusColor {
    if (item.isCompleted) return FerogoColors.success;
    if (item.isCancelled) return FerogoColors.danger;
    if (item.isNoShow)    return FerogoColors.warning;
    return FerogoColors.info;
  }

  String get _statusLabel {
    if (item.isCompleted) return 'Tamamlandı';
    if (item.isCancelled) return 'İptal';
    if (item.isNoShow)    return 'Gelinmedi';
    return item.status;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy · HH:mm', 'tr_TR');
    final dt = item.completedAt ?? item.createdAt;

    return Material(
      color: FerogoColors.inkSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text('Yolculuk detayı sonraki adımda gelecek (#${item.publicId}).'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: FerogoColors.inkMuted,
            ));
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusLabel.toUpperCase(),
                      style: TextStyle(color: _statusColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    df.format(dt.toLocal()),
                    style: const TextStyle(color: FerogoColors.textLow, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Row(icon: Icons.circle_outlined, text: item.pickupAddress, color: FerogoColors.brand),
              const SizedBox(height: 4),
              _Row(icon: Icons.place, text: item.dropoffAddress, color: FerogoColors.danger),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (item.vehicleClass != null) ...[
                    const Icon(Icons.local_taxi, size: 14, color: FerogoColors.textLow),
                    const SizedBox(width: 4),
                    Text(item.vehicleClass!, style: const TextStyle(color: FerogoColors.textMid, fontSize: 12)),
                    const SizedBox(width: 12),
                  ],
                  if (item.driverName != null) ...[
                    const Icon(Icons.person, size: 14, color: FerogoColors.textLow),
                    const SizedBox(width: 4),
                    Flexible(child: Text(item.driverName!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: FerogoColors.textMid, fontSize: 12),
                    )),
                  ],
                  const Spacer(),
                  if (item.totalFare != null)
                    Text('${item.totalFare!.toStringAsFixed(0)} ₺',
                      style: const TextStyle(color: FerogoColors.textHigh, fontWeight: FontWeight.w800),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: const TextStyle(color: FerogoColors.textHigh, fontSize: 13, height: 1.35),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        )),
      ],
    );
  }
}
