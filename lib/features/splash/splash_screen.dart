import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/ferogo_logo.dart';

/// Auth + mod state'leri okunurken görünür. Router bittiğinde otomatik
/// /mode, /customer/phone, /customer/home gibi hedefe atar.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FerogoColors.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.3,
                  colors: [
                    FerogoColors.brand.withValues(alpha: 0.18),
                    FerogoColors.ink,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FerogoLogo(size: 56),
                const SizedBox(height: 24),
                SizedBox(
                  width: 32, height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: FerogoColors.brand.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
