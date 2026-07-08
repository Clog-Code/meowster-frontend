import 'package:flutter/material.dart';

class PetTheme {
  static const ink = Color(0xFF0E1116);
  static const panel = Color(0xFF171B22);
  static const panelSoft = Color(0xFF202630);
  static const ivory = Color(0xFFF6F0E8);
  static const muted = Color(0xFFB8C0C9);
  static const aqua = Color(0xFF65D6D0);
  static const coral = Color(0xFFFF8A66);
  static const sage = Color(0xFFA5C68A);
  static const warning = Color(0xFFFFC857);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: aqua,
      brightness: Brightness.dark,
      surface: ink,
      primary: aqua,
      secondary: coral,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      useMaterial3: true,
      fontFamily: 'SF Pro Display',
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: ivory,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: ivory,
        displayColor: ivory,
        fontFamily: 'SF Pro Display',
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: aqua,
          foregroundColor: const Color(0xFF061010),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelSoft,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }
}
