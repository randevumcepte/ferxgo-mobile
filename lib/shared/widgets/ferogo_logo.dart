import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// FerXGo wordmark — splash, login üst başlıkları için.
/// Fer (beyaz) · X (altın, italik, büyük) · Go (beyaz).
/// Asset eklenince image versiyonuna geçilebilir; şu an typo-mark.
class FerogoLogo extends StatelessWidget {
  const FerogoLogo({super.key, this.size = 32, this.color, this.xColor});

  final double size;

  /// "Fer" ve "Go" rengi (varsayılan: beyaz/yüksek kontrast).
  final Color? color;

  /// Ortadaki "X" rengi (varsayılan: marka altın).
  final Color? xColor;

  @override
  Widget build(BuildContext context) {
    final base = color ?? FerogoColors.textHigh;
    final x    = xColor ?? FerogoColors.brand;
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
          height: 1.0,
        ),
        children: [
          TextSpan(text: 'Fer', style: TextStyle(color: base)),
          TextSpan(
            text: 'X',
            style: TextStyle(
              color: x,
              fontStyle: FontStyle.italic,
              fontSize: size * 1.22, // "A" oranı: X, gövdeden ~%22 büyük
            ),
          ),
          TextSpan(text: 'Go', style: TextStyle(color: base)),
        ],
      ),
    );
  }
}
