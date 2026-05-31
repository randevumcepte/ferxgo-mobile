import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/soon_card.dart';
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
              const SoonCard(
                icon: Icons.toggle_off_outlined,
                title: 'Çevrimiçi ol',
                subtitle: 'Müşteri taleplerini almaya başla.',
                snackBarMessage: 'Çevrimiçi/çevrimdışı toggle Faz 2\'de geliyor.',
              ),
              const SizedBox(height: 12),
              const SoonCard(
                icon: Icons.history,
                title: 'Tamamlanan yolculuklar',
                subtitle: 'Kazanç özetin ve geçmiş yolculuklar.',
                snackBarMessage: 'Kazanç ekranı Faz 2\'de geliyor.',
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
