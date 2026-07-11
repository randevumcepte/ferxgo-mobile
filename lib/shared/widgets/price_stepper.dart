import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// inDrive tarzı fiyat teklifi stepper'ı: büyük tutar + −/+ butonları.
/// [min]/[max] band'i backend'in suggested ±%40 sınırıyla eşleşir.
class PriceStepper extends StatelessWidget {
  const PriceStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.step = 10,
    this.currency = '₺',
    this.label,
    this.hint,
    this.dense = false,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;
  final double step;
  final String currency;
  final String? label;
  final String? hint;

  /// Dar ekranlarda daha kompakt görünüm (küçük yazı/buton/boşluk).
  final bool dense;

  void _bump(double delta) {
    var next = value + delta;
    if (min != null && next < min!) next = min!;
    if (max != null && next > max!) next = max!;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final canDec = min == null || value > min!;
    final canInc = max == null || value < max!;

    return Container(
      padding: dense ? const EdgeInsets.fromLTRB(12, 10, 12, 12) : const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: FerxgoColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FerxgoColors.brand.withValues(alpha: 0.40)),
      ),
      child: Column(
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: const TextStyle(
                color: FerxgoColors.textMid,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: dense ? 6 : 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepButton(icon: Icons.remove, enabled: canDec, dense: dense, onTap: () => _bump(-step)),
              Expanded(
                child: Center(
                  child: FittedBox(
                    child: Text(
                      '${value.toStringAsFixed(0)} $currency',
                      style: TextStyle(
                        color: FerxgoColors.textHigh,
                        fontSize: dense ? 30 : 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ),
              _StepButton(icon: Icons.add, enabled: canInc, dense: dense, onTap: () => _bump(step)),
            ],
          ),
          if (hint != null) ...[
            SizedBox(height: dense ? 6 : 8),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 12),
            ),
          ],
          if (min != null && max != null) ...[
            const SizedBox(height: 4),
            Text(
              'Aralık: ${min!.toStringAsFixed(0)} – ${max!.toStringAsFixed(0)} $currency',
              textAlign: TextAlign.center,
              style: const TextStyle(color: FerxgoColors.textLow, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.enabled, required this.onTap, this.dense = false});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final size = dense ? 42.0 : 48.0;
    return Material(
      color: enabled ? FerxgoColors.brand : FerxgoColors.inkMuted,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: enabled ? Colors.black : FerxgoColors.textLow,
            size: dense ? 23 : 26,
          ),
        ),
      ),
    );
  }
}
