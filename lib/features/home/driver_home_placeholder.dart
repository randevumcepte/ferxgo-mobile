import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../auth/auth_repository.dart';

/// Geçici sürücü dashboard placeholder.
/// Faz 2'de: state polling + online/offline toggle + offer modal + active ride.
class DriverHomePlaceholder extends ConsumerWidget {
  const DriverHomePlaceholder({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value?.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ferogo Sürücü'),
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
                'Hoş geldin, ${user?.name ?? 'Sürücü'} 🚖',
                style: const TextStyle(color: FerogoColors.textHigh, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Faz 2: çevrimiçi/çevrimdışı, teklif kabulü, aktif yolculuk burada olacak.',
                style: TextStyle(color: FerogoColors.textLow, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: FerogoColors.brand.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.toggle_off_outlined, color: FerogoColors.brand, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Çevrimdışı',
                              style: TextStyle(color: FerogoColors.textHigh, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 4),
                            Text('Aç düğmesi sonraki turda gelecek.',
                              style: TextStyle(color: FerogoColors.textMid, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const Center(
                child: Text(
                  'Faz 1 · iskelet hazır',
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
