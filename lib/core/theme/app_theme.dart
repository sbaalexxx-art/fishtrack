import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'fluviai_commercial_tokens.dart';

class AppTheme {
  AppTheme._();

  static final ThemeData lightTheme = _build(Brightness.light);
  static final ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? FluviAIThemeColors.dark : FluviAIThemeColors.light;
    final background = palette.background;
    final surface = palette.surface;
    final surfaceRaised = palette.surfaceRaised;
    final onSurface = palette.textPrimary;
    final onSurfaceVariant = palette.textSecondary;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: FluviAICommercialTokens.accent,
      onPrimary: const Color(0xFF001F27),
      primaryContainer: FluviAICommercialTokens.accentSoft,
      onPrimaryContainer: onSurface,
      secondary: FluviAICommercialTokens.brandFocus,
      onSecondary: const Color(0xFF001F27),
      secondaryContainer: surfaceRaised,
      onSecondaryContainer: onSurface,
      error: FluviAICommercialTokens.waterFalling,
      onError: Colors.white,
      errorContainer: FluviAICommercialTokens.waterFalling.withValues(
        alpha: .16,
      ),
      onErrorContainer: onSurface,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: palette.border,
      outlineVariant: palette.borderSoft,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: onSurface,
      onInverseSurface: surface,
      inversePrimary: FluviAICommercialTokens.brandFocus,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: FluviAICommercialTokens.fontFamily,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[palette],

      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: background,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: background,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        hintStyle: TextStyle(color: palette.textSecondary),
        prefixIconColor: palette.textSecondary,
        suffixIconColor: palette.textSecondary,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF001F27),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceRaised,
        selectedColor: FluviAICommercialTokens.accent.withValues(alpha: .16),
        side: BorderSide(color: palette.borderSoft),
        labelStyle: TextStyle(color: onSurfaceVariant),
        secondaryLabelStyle: TextStyle(color: onSurface),
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return FluviAICommercialTokens.accent.withValues(alpha: .16);
            }
            return surfaceRaised;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark
                  ? FluviAICommercialTokens.accent
                  : FluviAICommercialTokens.accentDeep;
            }
            return onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: palette.borderSoft)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.navigationBackground,
        indicatorColor: FluviAICommercialTokens.accent.withValues(alpha: .16),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? FluviAICommercialTokens.accentDeep
                : palette.navigationInactive,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? (isDark
                      ? FluviAICommercialTokens.accent
                      : FluviAICommercialTokens.accentDeep)
                : palette.navigationInactive,
          ),
        ),
      ),
    );
  }
}
