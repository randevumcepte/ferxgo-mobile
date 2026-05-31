import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Henüz hazır olmayan ekranların yer tutucusu.
/// Tıklanır: InkWell + "Yakında" SnackBar.
/// Kural: tıklanır gibi görünen her şey gerçekten tıklanmalı.
class SoonCard extends StatelessWidget {
  const SoonCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.snackBarMessage,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? snackBarMessage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(snackBarMessage ?? 'Yakında — sonraki sürümde geliyor.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: FerogoColors.inkMuted,
            ));
        },
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(title,
                            style: const TextStyle(
                              color: FerogoColors.textHigh,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: FerogoColors.brand.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'YAKINDA',
                            style: TextStyle(
                              color: FerogoColors.brand,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: FerogoColors.textMid, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: FerogoColors.textLow, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
