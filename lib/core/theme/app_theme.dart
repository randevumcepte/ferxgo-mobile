import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Ferogo Material 3 teması. Default koyu mod (gece sürüş + harita kontrastı için).
/// Açık mod da var; sistem ayarını takip eder.
class FerogoTheme {
  FerogoTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: FerogoColors.brand,
      brightness: Brightness.dark,
      primary: FerogoColors.brand,
      onPrimary: Colors.black,
      surface: FerogoColors.inkSoft,
      onSurface: FerogoColors.textHigh,
      surfaceContainerHighest: FerogoColors.inkMuted,
      outline: FerogoColors.line,
      error: FerogoColors.danger,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: FerogoColors.ink,
      appBarTheme: AppBarTheme(
        backgroundColor: FerogoColors.ink,
        foregroundColor: FerogoColors.textHigh,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: FerogoColors.textHigh,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: FerogoColors.inkSoft,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: FerogoColors.line),
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
      seedColor: FerogoColors.brand,
      brightness: Brightness.light,
      primary: FerogoColors.brand,
      onPrimary: Colors.black,
      surface: FerogoColors.paper,
      onSurface: FerogoColors.textInkHigh,
      outline: FerogoColors.paperLine,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: FerogoColors.paperAlt,
      appBarTheme: AppBarTheme(
        backgroundColor: FerogoColors.paper,
        foregroundColor: FerogoColors.textInkHigh,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: FerogoColors.textInkHigh,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: FerogoColors.paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: FerogoColors.paperLine),
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
    final fill = dark ? FerogoColors.inkMuted : FerogoColors.paper;
    final border = dark ? FerogoColors.line : FerogoColors.paperLine;
    final hint = dark ? FerogoColors.textLow : FerogoColors.textInkMid;
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
        borderSide: const BorderSide(color: FerogoColors.brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FerogoColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FerogoColors.danger, width: 2),
      ),
    );
  }

  static FilledButtonThemeData _filledButton() => FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FerogoColors.brand,
          foregroundColor: Colors.black,
          disabledBackgroundColor: FerogoColors.brand.withValues(alpha: 0.35),
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
          foregroundColor: dark ? FerogoColors.textHigh : FerogoColors.textInkHigh,
          minimumSize: const Size(double.infinity, 54),
          side: BorderSide(color: dark ? FerogoColors.line : FerogoColors.paperLine),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );

  static TextButtonThemeData _textButton() => TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: FerogoColors.brand,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
}
