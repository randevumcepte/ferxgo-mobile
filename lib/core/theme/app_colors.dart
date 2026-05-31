import 'package:flutter/material.dart';

/// Ferogo marka palet — web ile birebir uyumlu.
/// Web tailwind config:
///   brand DEFAULT/500: #F0C040
///   brand 50:  #FEF9E7
///   brand 100: #FDF0C1
///   brand 600: #D9A621
///   brand 700: #B68918
class FerogoColors {
  FerogoColors._();

  // Ana marka rengi (sarı amber)
  static const Color brand50  = Color(0xFFFEF9E7);
  static const Color brand100 = Color(0xFFFDF0C1);
  static const Color brand200 = Color(0xFFFCE69A);
  static const Color brand300 = Color(0xFFF7D572);
  static const Color brand400 = Color(0xFFF4CB56);
  static const Color brand    = Color(0xFFF0C040); // 500 / DEFAULT
  static const Color brand600 = Color(0xFFD9A621);
  static const Color brand700 = Color(0xFFB68918);
  static const Color brand800 = Color(0xFF8C6912);
  static const Color brand900 = Color(0xFF5C440B);

  // Yüzeyler — koyu mod öncelikli mobil (gece sürüş + harita için)
  static const Color ink      = Color(0xFF0B0B0F); // app background
  static const Color inkSoft  = Color(0xFF14141B); // card / surface
  static const Color inkMuted = Color(0xFF1E1E27); // elevated surface
  static const Color line     = Color(0xFF2A2A36);

  // Açık mod yüzeyleri
  static const Color paper    = Color(0xFFFFFFFF);
  static const Color paperAlt = Color(0xFFF7F7F9);
  static const Color paperLine= Color(0xFFE5E7EB);

  // Metin
  static const Color textHigh   = Color(0xFFFFFFFF);
  static const Color textMid    = Color(0xFFC7C7D1);
  static const Color textLow    = Color(0xFF9090A0);
  static const Color textInkHigh= Color(0xFF111118);
  static const Color textInkMid = Color(0xFF4B4B59);

  // Semantik
  static const Color success  = Color(0xFF22C55E);
  static const Color warning  = Color(0xFFEAB308);
  static const Color danger   = Color(0xFFEF4444);
  static const Color info     = Color(0xFF3B82F6);
}
