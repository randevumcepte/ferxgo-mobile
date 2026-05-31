import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_repository.dart';

/// Geçici müşteri home — Faz 1'in sonraki turunda harita ve rezervasyon flow'u burada olacak.
/// Şimdilik /me'den dönen profili gösterir ve çıkışı test edebilmemizi sağlar.
class CustomerHomePlaceholder extends ConsumerWidget {
  const CustomerHomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final user    = session?.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ferogo'),
        actions: [
          IconButton(
            tooltip: 'Çıkış',
            onPressed: () => ref.read(authRepositoryProvider).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hoş geldin${user != null ? ', ${user.name}' : ''} 👋',
                style: const TextStyle(color: FerogoColors.textHigh, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                user?.phone ?? '',
                style: const TextStyle(color: FerogoColors.textLow, fontSize: 14),
              ),
              const SizedBox(height: 28),
              _PlaceholderCard(
                icon: Icons.map_outlined,
                title: 'Yakındaki sürücüler',
                subtitle: 'Sonraki adımda burası canlı harita olacak.',
              ),
              const SizedBox(height: 12),
              _PlaceholderCard(
                icon: Icons.history,
                title: 'Geçmiş yolculuklar',
                subtitle: 'Daha önce yaptığın yolculuklar buraya gelecek.',
              ),
              const Spacer(),
              const Center(
                child: Text(
                  'Faz 1 · iskelet hazır · sonraki: harita + ride flow',
                  style: TextStyle(color: FerogoColors.textLow, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: FerogoColors.brand.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: FerogoColors.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: FerogoColors.textHigh, fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: FerogoColors.textMid, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
