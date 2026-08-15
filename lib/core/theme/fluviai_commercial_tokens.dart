import 'package:flutter/material.dart';

/// Canonical visual language for the production FluviAI experience.
///
/// Values mirror the approved Figma UI/UX Release Candidate v2. Runtime data,
/// entitlement and connectivity remain dynamic; these tokens define only the
/// shared visual contract used by Android and iOS.
abstract final class FluviAICommercialTokens {
  /// Bundled primary UI font used by the approved production design.
  static const primaryFontFamily = 'Geist';

  /// Bundled monospace font for data and technical values.
  static const monoFontFamily = 'IBM Plex Mono';

  /// Compatibility alias used by existing presentation code.
  static const fontFamily = primaryFontFamily;

  static const background = Color(0xFF050B14);
  static const backgroundRaised = Color(0xFF071321);
  static const surface = Color(0xFF0A1628);
  static const surfaceRaised = Color(0xFF0D2033);
  static const surfaceStrong = Color(0xFF112B40);
  static const border = Color(0xFF133750);
  static const borderSoft = Color(0x33133750);

  static const textPrimary = Color(0xFFF6F9FB);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);

  static const accent = Color(0xFF43D9CC);
  static const accentDeep = Color(0xFF007394);
  static const accentSoft = Color(0x2643D9CC);
  static const brandFocus = Color(0xFF43D9CC);

  static const waterRising = Color(0xFF43D9CC);
  static const waterStable = Color(0xFF00E676);
  static const waterFalling = Color(0xFFFA4F4F);
  static const warning = Color(0xFFF0BD55);
  static const premium = Color(0xFFF0BD55);

  static const radiusSmall = 12.0;
  static const radiusMedium = 16.0;
  static const radiusLarge = 20.0;
  static const radiusHero = 24.0;

  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;

  static const minimumTouchTarget = 48.0;

  // Approved Bento shell navigation contract (Figma 329:111 / 445:10-14).
  static const bottomNavigationVisualHeight = 60.0;
  static const bottomNavigationHorizontalMargin = 16.0;
  static const bottomNavigationRadius = 20.0;
  static const bottomNavigationQuickAddWidth = 52.0;
  static const bottomNavigationQuickAddVisualHeight = 46.0;
  static const bottomNavigationQuickAddRadius = 16.0;
  static const bottomNavigationIconSize = 19.0;
  static const bottomNavigationLabelSize = 11.0;

  static const bottomNavigationBackground = Color(0xFF071015);
  static const bottomNavigationInactive = Color(0xFF9AABB4);
  static const bottomNavigationBorder = Color(0xD1263941);

  static List<BoxShadow> get softShadow => const [
    BoxShadow(color: Color(0x47000000), blurRadius: 12, offset: Offset(0, 10)),
  ];

  static List<BoxShadow> get heroShadow => const [
    BoxShadow(color: Color(0x47000000), blurRadius: 14, offset: Offset(0, 12)),
  ];

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A1628), background, Color(0xFF03070D)],
    stops: [0, .52, 1],
  );

  static const LinearGradient bottomNavigationGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xD9050B14), background],
  );

  static LinearGradient surfaceGradient({Color? accent}) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(
        (accent ?? FluviAICommercialTokens.brandFocus).withValues(alpha: .055),
        surfaceRaised,
      ),
      surface,
    ],
  );
}

/// Theme-aware neutral palette. Brand and semantic water colors remain
/// canonical in [FluviAICommercialTokens]; only surfaces and readable content
/// adapt to the active platform/app brightness.
@immutable
class FluviAIThemeColors extends ThemeExtension<FluviAIThemeColors> {
  const FluviAIThemeColors({
    required this.background,
    required this.backgroundRaised,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceStrong,
    required this.border,
    required this.borderSoft,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.navigationBackground,
    required this.navigationInactive,
    required this.navigationBorder,
  });

  // The approved Home Premium/Bento surface is the canonical neutral dark
  // family. Main tabs must consume this same hierarchy instead of drifting
  // between legacy blue/navy palettes. Semantic Water/Hydro/Weather accents
  // remain owned by [FluviAICommercialTokens].
  static const dark = FluviAIThemeColors(
    background: Color(0xFF05090C),
    backgroundRaised: Color(0xFF071216),
    surface: Color(0xFF101C22),
    surfaceRaised: Color(0xFF0D171C),
    surfaceStrong: Color(0xFF0A151A),
    border: Color(0xFF263941),
    borderSoft: Color(0x66263941),
    textPrimary: Color(0xFFF4F8FA),
    textSecondary: Color(0xFF9AABB4),
    textMuted: Color(0xFF8497A0),
    navigationBackground: Color(0xFF101C22),
    navigationInactive: Color(0xFF9AABB4),
    navigationBorder: Color(0x99263941),
  );

  static const light = FluviAIThemeColors(
    background: Color(0xFFF3F8FA),
    backgroundRaised: Color(0xFFEAF3F6),
    surface: Color(0xFFFAFDFE),
    surfaceRaised: Color(0xFFE8F1F4),
    surfaceStrong: Color(0xFFDDEBEF),
    border: Color(0xFFB7C8D0),
    borderSoft: Color(0x66B7C8D0),
    textPrimary: Color(0xFF10202B),
    textSecondary: Color(0xFF4E6674),
    textMuted: Color(0xFF697E89),
    navigationBackground: Color(0xFFF8FCFD),
    navigationInactive: Color(0xFF5B707C),
    navigationBorder: Color(0x99B7C8D0),
  );

  final Color background;
  final Color backgroundRaised;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceStrong;
  final Color border;
  final Color borderSoft;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color navigationBackground;
  final Color navigationInactive;
  final Color navigationBorder;

  LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundRaised, background, surface],
    stops: const [0, .52, 1],
  );

  static FluviAIThemeColors of(BuildContext context) =>
      Theme.of(context).extension<FluviAIThemeColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  FluviAIThemeColors copyWith({
    Color? background,
    Color? backgroundRaised,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceStrong,
    Color? border,
    Color? borderSoft,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? navigationBackground,
    Color? navigationInactive,
    Color? navigationBorder,
  }) => FluviAIThemeColors(
    background: background ?? this.background,
    backgroundRaised: backgroundRaised ?? this.backgroundRaised,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceStrong: surfaceStrong ?? this.surfaceStrong,
    border: border ?? this.border,
    borderSoft: borderSoft ?? this.borderSoft,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    navigationBackground: navigationBackground ?? this.navigationBackground,
    navigationInactive: navigationInactive ?? this.navigationInactive,
    navigationBorder: navigationBorder ?? this.navigationBorder,
  );

  @override
  FluviAIThemeColors lerp(covariant FluviAIThemeColors? other, double t) {
    if (other == null) return this;
    return FluviAIThemeColors(
      background: Color.lerp(background, other.background, t)!,
      backgroundRaised: Color.lerp(
        backgroundRaised,
        other.backgroundRaised,
        t,
      )!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceStrong: Color.lerp(surfaceStrong, other.surfaceStrong, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      navigationBackground: Color.lerp(
        navigationBackground,
        other.navigationBackground,
        t,
      )!,
      navigationInactive: Color.lerp(
        navigationInactive,
        other.navigationInactive,
        t,
      )!,
      navigationBorder: Color.lerp(
        navigationBorder,
        other.navigationBorder,
        t,
      )!,
    );
  }
}
