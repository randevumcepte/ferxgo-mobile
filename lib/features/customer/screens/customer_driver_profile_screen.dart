import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../customer_ride_repository.dart';

/// Yolcunun sürücüyü SEÇMEDEN önce inceleyebilmesi için profil + yorumlar.
class CustomerDriverProfileScreen extends ConsumerStatefulWidget {
  const CustomerDriverProfileScreen({super.key, required this.driverId, this.driverName});
  final int driverId;
  final String? driverName;

  @override
  ConsumerState<CustomerDriverProfileScreen> createState() => _CustomerDriverProfileScreenState();
}

class _CustomerDriverProfileScreenState extends ConsumerState<CustomerDriverProfileScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(customerRideRepositoryProvider).driverProfile(widget.driverId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FerxgoColors.ink,
      appBar: AppBar(title: Text(widget.driverName ?? 'Sürücü profili')),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: FerxgoColors.brand));
            }
            if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Sürücü bilgisi yüklenemedi.',
                    style: TextStyle(color: FerxgoColors.textMid)),
                ),
              );
            }
            final d = snap.data!;
            final rating = (d['rating'] as num?)?.toDouble() ?? 0;
            final ratingCount = (d['rating_count'] as num?)?.toInt() ?? 0;
            final totalRides = (d['total_rides'] as num?)?.toInt() ?? 0;
            final reviews = (d['reviews'] as List? ?? const []).whereType<Map>().toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Üst kimlik
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: FerxgoColors.inkMuted,
                      backgroundImage: (d['avatar'] is String && (d['avatar'] as String).isNotEmpty)
                          ? NetworkImage(d['avatar'] as String) : null,
                      child: (d['avatar'] == null || (d['avatar'] as String).isEmpty)
                          ? const Icon(Icons.person, color: FerxgoColors.textMid, size: 32) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((d['short_name'] as String?) ?? widget.driverName ?? 'Sürücü',
                            style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: FerxgoColors.brand, size: 20),
                              const SizedBox(width: 4),
                              Text(rating.toStringAsFixed(2),
                                style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 15, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Text('$ratingCount değerlendirme · $totalRides yolculuk',
                                style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Text('Yolcu Yorumları',
                  style: const TextStyle(color: FerxgoColors.textMid, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),

                if (reviews.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Henüz yorum yok.',
                      style: TextStyle(color: FerxgoColors.textLow))),
                  )
                else
                  ...reviews.map((r) => _ReviewCard(data: Map<String, dynamic>.from(r))),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final stars = (data['stars'] as num?)?.toInt() ?? 0;
    final review = data['review'] as String?;
    final reviewer = (data['reviewer_name'] as String?)?.trim();
    final date = data['completed_at'] is String ? DateTime.tryParse(data['completed_at'] as String) : null;
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
              Expanded(
                child: Text(
                  (reviewer != null && reviewer.isNotEmpty) ? reviewer : 'Yolcu',
                  style: const TextStyle(
                      color: FerxgoColors.textHigh, fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (date != null)
                Text(df.format(date.toLocal()),
                  style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: FerxgoColors.brand, size: 16),
            ],
          ),
          if (review != null && review.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review, style: const TextStyle(color: FerxgoColors.textHigh, fontSize: 14, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
