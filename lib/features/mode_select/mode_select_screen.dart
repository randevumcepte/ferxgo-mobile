import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../app_mode/app_mode.dart';
import '../../shared/widgets/ferogo_logo.dart';

class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: FerogoColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FerogoLogo(size: 28),
              const Spacer(),
              const Text(
                'Hangi taraftan başlıyoruz?',
                style: TextStyle(
                  color: FerogoColors.textHigh,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bu seçimi sonra ayarlardan değiştirebilirsin.',
                style: TextStyle(color: FerogoColors.textLow, fontSize: 14),
              ),
              const SizedBox(height: 28),
              _ModeCard(
                icon: Icons.person_pin_circle_outlined,
                title: 'Yolculuk yapacağım',
                subtitle: 'Yakındaki sürücüleri gör, telefonla giriş yap, hemen yola çık.',
                cta: 'Müşteri olarak devam et',
                onTap: () async {
                  await ref.read(appModeControllerProvider.notifier).set(AppMode.customer);
                },
              ),
              const SizedBox(height: 14),
              _ModeCard(
                icon: Icons.local_taxi_outlined,
                title: 'Sürücüyüm',
                subtitle: 'Onaylı sürücü hesabınla gir, müşteri tekliflerini al.',
                cta: 'Sürücü olarak devam et',
                onTap: () async {
                  await ref.read(appModeControllerProvider.notifier).set(AppMode.driver);
                },
              ),
              const Spacer(),
              const Center(
                child: Text(
                  '© Ferogo · İzmir',
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FerogoColors.inkSoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: FerogoColors.brand.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: FerogoColors.brand, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: const TextStyle(
                        color: FerogoColors.textHigh,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                      style: const TextStyle(
                        color: FerogoColors.textMid,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(cta,
                          style: const TextStyle(
                            color: FerogoColors.brand,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward, size: 16, color: FerogoColors.brand),
                      ],
                    ),
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
