import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/soon_card.dart';
import '../auth/auth_repository.dart';

/// Geçici müşteri home — Faz 1'in sonraki turunda harita ve rezervasyon flow'u burada olacak.
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
              const SoonCard(
                icon: Icons.map_outlined,
                title: 'Yakındaki sürücüler',
                subtitle: 'Canlı harita + sürücü seçimi burada olacak.',
                snackBarMessage: 'Harita ekranı sonraki sürümde geliyor.',
              ),
              const SizedBox(height: 12),
              const SoonCard(
                icon: Icons.history,
                title: 'Geçmiş yolculuklar',
                subtitle: 'Tamamlanmış yolculukların listesi.',
                snackBarMessage: 'Geçmiş ekranı sonraki sürümde geliyor.',
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
