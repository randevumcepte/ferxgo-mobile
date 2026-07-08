import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// FerXGo Material 3 teması. Default koyu mod (gece sürüş + harita kontrastı için).
/// Açık mod da var; sistem ayarını takip eder.
class FerxgoTheme {
  FerxgoTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: FerxgoColors.brand,
      brightness: Brightness.dark,
      primary: FerxgoColors.brand,
      onPrimary: Colors.black,
      surface: FerxgoColors.inkSoft,
      onSurface: FerxgoColors.textHigh,
      surfaceContainerHighest: FerxgoColors.inkMuted,
      outline: FerxgoColors.line,
      error: FerxgoColors.danger,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: FerxgoColors.ink,
      appBarTheme: AppBarTheme(
        backgroundColor: FerxgoColors.ink,
        foregroundColor: FerxgoColors.textHigh,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: FerxgoColors.textHigh,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: FerxgoColors.inkSoft,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: FerxgoColors.line),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: _inputDecoration(dark: true),
      filledButtonTheme: _filledButton(),
      outlinedButtonTheme: _outlinedButton(dark: true),
      textButtonTheme: _textButton(),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: FerxgoColors.brand,
      brightness: Brightness.light,
      primary: FerxgoColors.brand,
      onPrimary: Colors.black,
      surface: FerxgoColors.paper,
      onSurface: FerxgoColors.textInkHigh,
      outline: FerxgoColors.paperLine,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: FerxgoColors.paperAlt,
      appBarTheme: AppBarTheme(
        backgroundColor: FerxgoColors.paper,
        foregroundColor: FerxgoColors.textInkHigh,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: FerxgoColors.textInkHigh,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: FerxgoColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: FerxgoColors.paperLine),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: _inputDecoration(dark: false),
      filledButtonTheme: _filledButton(),
      outlinedButtonTheme: _outlinedButton(dark: false),
      textButtonTheme: _textButton(),
    );
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        visualDensity: VisualDensity.standard,
        splashFactory: InkRipple.splashFactory,
      );

  static InputDecorationTheme _inputDecoration({required bool dark}) {
    final fill = dark ? FerxgoColors.inkMuted : FerxgoColors.paper;
    final border = dark ? FerxgoColors.line : FerxgoColors.paperLine;
    final hint = dark ? FerxgoColors.textLow : FerxgoColors.textInkMid;
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      hintStyle: TextStyle(color: hint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FerxgoColors.brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FerxgoColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FerxgoColors.danger, width: 2),
      ),
    );
  }

  static FilledButtonThemeData _filledButton() => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FerxgoColors.brand,
          foregroundColor: Colors.black,
          disabledBackgroundColor: FerxgoColors.brand.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.black54,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      );

  static OutlinedButtonThemeData _outlinedButton({required bool dark}) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? FerxgoColors.textHigh : FerxgoColors.textInkHigh,
          minimumSize: const Size(double.infinity, 54),
          side: BorderSide(color: dark ? FerxgoColors.line : FerxgoColors.paperLine),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );

  static TextButtonThemeData _textButton() => TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: FerxgoColors.brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
}
