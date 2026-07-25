import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../driver_repository.dart';

final _driverReviewsProvider = FutureProvider.autoDispose<DriverReviews>((ref) {
  return ref.watch(driverRepositoryProvider).reviews();
});

/// Sürücünün kendi hakkındaki yolcu değerlendirmeleri (puan + yorum).
class DriverReviewsScreen extends ConsumerWidget {
  const DriverReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_driverReviewsProvider);

    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(title: const Text('Değerlendirmelerim')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: FerxgoColors.brand)),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Değerlendirmeler yüklenemedi.\n$e',
                textAlign: TextAlign.center,
                style: const TextStyle(color: FerxgoColors.textMid)),
            ),
          ),
          data: (data) => RefreshIndicator(
            color: FerxgoColors.brand,
            onRefresh: () async => ref.refresh(_driverReviewsProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Özet: ortalama + toplam
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
                      Text(data.average.toStringAsFixed(2),
                        style: const TextStyle(color: FerxgoColors.brand, fontSize: 40, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Stars(value: data.average.round(), size: 22),
                            const SizedBox(height: 4),
                            Text('${data.count} değerlendirme',
                              style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (data.reviews.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text('Henüz değerlendirme yok.\nİlk yolculukların tamamlanınca burada görünecek.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: FerxgoColors.textLow, height: 1.5)),
                    ),
                  )
                else
                  ...data.reviews.map((r) => _ReviewCard(review: r)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final DriverReview review;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM yyyy', 'tr_TR');
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
          Row(
            children: [
              _Stars(value: review.stars, size: 16),
              const Spacer(),
              if (review.completedAt != null)
                Text(df.format(review.completedAt!.toLocal()),
                  style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
            ],
          ),
          if (review.review != null && review.review!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.review!,
              style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 14, height: 1.4)),
          ] else ...[
            const SizedBox(height: 6),
            const Text('Yorum bırakılmadı',
              style: TextStyle(color: FerxgoColors.textLow, fontSize: 13, fontStyle: FontStyle.italic)),
          ],
          if ((review.pickup ?? '').isNotEmpty || (review.dropoff ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${review.pickup ?? ''} → ${review.dropoff ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.size = 18});
  final int value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            color: FerxgoColors.brand, size: size),
      ],
    );
  }
}
