import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static final ThemeData lightTheme = _build(Brightness.light);
  static final ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF101418)
          : const Color(0xFFF5F7FA),

      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: isDark
            ? const Color(0xFF101418)
            : const Color(0xFFF5F7FA),
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),

      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1B2229) : Colors.white,
        elevation: isDark ? 1 : 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B2229) : Colors.white,
        border: const OutlineInputBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}
