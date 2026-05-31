import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Ferogo wordmark — splash, login üst başlıkları için.
/// Asset eklenince image versiyonuna geçilecek; şu an typo-mark.
class FerogoLogo extends StatelessWidget {
  const FerogoLogo({super.key, this.size = 32, this.color, this.dotColor});

  final double size;
  final Color? color;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final c    = color ?? FerogoColors.textHigh;
    final dot  = dotColor ?? FerogoColors.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'ferogo',
          style: TextStyle(
            color: c,
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
            height: 1.0,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: size * 0.08, bottom: size * 0.12),
          child: Container(
            width: size * 0.18,
            height: size * 0.18,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}
