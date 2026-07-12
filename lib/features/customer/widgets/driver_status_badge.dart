import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/nearby_driver.dart';

/// Favori sürücü canlı durum rozeti: 🟢 Müsait · 🟡 Yolculukta · ⚪ Çevrimdışı.
class DriverStatusBadge extends StatelessWidget {
  const DriverStatusBadge({super.key, required this.driver});
  final NearbyDriver driver;

  @override
  Widget build(BuildContext context) {
    final Color color = driver.isOnline
        ? FerxgoColors.success
        : driver.isBusy
            ? FerxgoColors.warning
            : FerxgoColors.textLow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            driver.statusLabel,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
