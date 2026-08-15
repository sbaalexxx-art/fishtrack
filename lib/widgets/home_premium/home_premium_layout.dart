import 'package:flutter/material.dart';

class HomePremiumLayout {
  const HomePremiumLayout._({
    required this.bodyViewportSize,
    required this.systemSafeArea,
    required this.bottomNavigationOverlaysBody,
    required this.isPortrait,
    required this.isLandscape,
    required this.isLandscapePhone,
    required this.isSmallPhone,
    required this.isNormalPhone,
    required this.isLargePhone,
    required this.isTablet,
    required this.horizontalPadding,
    required this.sectionGap,
    required this.usableHeight,
    required this.headerHeight,
    required this.heroMapHeight,
    required this.waterCardHeight,
    required this.weatherCardHeight,
    required this.standardSectionHeight,
    required this.recentCatchesHeight,
    required this.bottomNavHeight,
    required this.scrollClearance,
    required this.bottomContentClearance,
    required this.dashboardAreaHeight,
    required this.dashboardCardHeight,
    required this.bottomSafeClearance,
    required this.titleFontScale,
    required this.bodyFontScale,
    required this.iconScale,
  });

  factory HomePremiumLayout.of(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final usableHeight = _nonNegativeFinite(
      screenSize.height - viewPadding.top - viewPadding.bottom,
    );

    // This compatibility path derives a body-like size from the full screen.
    // Use fromViewport when LayoutBuilder supplies the actual Scaffold body.
    return _calculate(
      bodyViewportSize: Size(screenSize.width, usableHeight),
      classificationSize: screenSize,
      orientationSize: screenSize,
      systemSafeArea: viewPadding,
      bottomNavigationOverlaysBody: true,
    );
  }

  factory HomePremiumLayout.fromViewport(
    BuildContext context, {
    required Size viewportSize,
    EdgeInsets? systemSafeArea,
    double? bottomNavigationHeight,
    bool bottomNavigationOverlaysBody = false,
  }) {
    final bodyViewportSize = Size(
      _nonNegativeFinite(viewportSize.width),
      _nonNegativeFinite(viewportSize.height),
    );

    // LayoutBuilder reports the real body viewport, unlike MediaQuery's full
    // screen size. A Scaffold bottomNavigationBar is outside this viewport.
    return _calculate(
      bodyViewportSize: bodyViewportSize,
      classificationSize: bodyViewportSize,
      orientationSize: bodyViewportSize,
      systemSafeArea: systemSafeArea ?? MediaQuery.viewPaddingOf(context),
      bottomNavigationHeight: bottomNavigationHeight,
      bottomNavigationOverlaysBody: bottomNavigationOverlaysBody,
    );
  }

  static HomePremiumLayout _calculate({
    required Size bodyViewportSize,
    required Size classificationSize,
    required Size orientationSize,
    required EdgeInsets systemSafeArea,
    required bool bottomNavigationOverlaysBody,
    double? bottomNavigationHeight,
  }) {
    final usableHeight = bodyViewportSize.height;
    final isLandscape = orientationSize.width > orientationSize.height;
    final isPortrait = !isLandscape;
    final shortestSide = classificationSize.shortestSide;
    final isTablet = shortestSide >= 600;
    final isLandscapePhone = isLandscape && !isTablet;
    final isSmallPhone = !isTablet && shortestSide <= 360;
    final isNormalPhone =
        !isTablet && shortestSide > 360 && shortestSide <= 430;
    final isLargePhone = !isTablet && shortestSide > 430;

    double bounded(double value, double minimum, double maximum) =>
        value.clamp(minimum, maximum).toDouble();

    late final double horizontalPadding;
    late final double sectionGap;
    late final double headerHeight;
    late final double bottomNavHeight;
    late final double heroMapHeight;
    late final double waterCardHeight;
    late final double weatherCardHeight;
    late final double standardSectionHeight;
    late final double recentCatchesHeight;
    late final double titleFontScale;
    late final double bodyFontScale;
    late final double iconScale;

    double resolveBottomNavigationHeight(double calculatedHeight) =>
        bottomNavigationHeight == null
        ? calculatedHeight
        : _nonNegativeFinite(bottomNavigationHeight);

    if (isTablet) {
      horizontalPadding = bounded(
        shortestSide * .025,
        18,
        isLandscape ? 26 : 22,
      );
      titleFontScale = 1.08;
      bodyFontScale = 1.05;
      iconScale = 1.10;
    } else if (isLandscape) {
      horizontalPadding = bounded(shortestSide * .025, 8, 12);
      titleFontScale = .90;
      bodyFontScale = .90;
      iconScale = .90;
    } else if (isSmallPhone) {
      horizontalPadding = bounded(shortestSide * .025, 8, 9);
      titleFontScale = .90;
      bodyFontScale = .90;
      iconScale = .90;
    } else if (isNormalPhone) {
      horizontalPadding = bounded(shortestSide * .024, 8, 10);
      titleFontScale = .95;
      bodyFontScale = .95;
      iconScale = .95;
    } else if (isLargePhone) {
      horizontalPadding = bounded(shortestSide * .023, 9, 11);
      titleFontScale = 1;
      bodyFontScale = 1;
      iconScale = 1;
    }

    if (isLandscapePhone) {
      const landscapePhoneMinimumGap = 4.0;
      const landscapePhoneMaximumGap = 6.0;
      const landscapePhoneMinimumHeaderHeight = 48.0;
      const landscapePhoneMaximumHeaderHeight = 56.0;
      const landscapePhoneMinimumNavigationHeight = 52.0;
      const landscapePhoneMaximumNavigationHeight = 58.0;
      const landscapePhoneMinimumMapHeight = 150.0;
      const landscapePhoneMaximumMapHeight = 230.0;
      const landscapePhoneMinimumWaterHeight = 146.0;
      const landscapePhoneMaximumWaterHeight = 164.0;
      const landscapePhoneMinimumWeatherHeight = 108.0;
      const landscapePhoneMaximumWeatherHeight = 122.0;
      const landscapePhoneMinimumStandardSectionHeight = 126.0;
      const landscapePhoneMaximumStandardSectionHeight = 142.0;
      const landscapePhoneMinimumRecentCatchesHeight = 156.0;
      const landscapePhoneMaximumRecentCatchesHeight = 184.0;
      const landscapePhoneHeaderSpacingFactor = 1.75;
      const landscapePhoneMapHeightFactor = .62;
      const landscapePhoneWaterHeightFactor = .46;
      const landscapePhoneWeatherHeightFactor = .34;
      const landscapePhoneStandardSectionHeightFactor = .40;
      const landscapePhoneRecentCatchesHeightFactor = .48;

      sectionGap = bounded(
        usableHeight * .012,
        landscapePhoneMinimumGap,
        landscapePhoneMaximumGap,
      );
      headerHeight = bounded(
        usableHeight * .16,
        landscapePhoneMinimumHeaderHeight,
        landscapePhoneMaximumHeaderHeight,
      );
      bottomNavHeight = resolveBottomNavigationHeight(
        bounded(
          usableHeight * .14,
          landscapePhoneMinimumNavigationHeight,
          landscapePhoneMaximumNavigationHeight,
        ),
      );
      final firstHomeViewportHeight = bounded(
        usableHeight - (bottomNavigationOverlaysBody ? bottomNavHeight : 0),
        0,
        usableHeight,
      );
      final mapHeightBudget = bounded(
        firstHomeViewportHeight -
            headerHeight -
            (sectionGap * landscapePhoneHeaderSpacingFactor),
        0,
        firstHomeViewportHeight,
      );
      final proportionalMapHeight = bounded(
        firstHomeViewportHeight * landscapePhoneMapHeightFactor,
        landscapePhoneMinimumMapHeight,
        landscapePhoneMaximumMapHeight,
      );
      heroMapHeight = proportionalMapHeight
          .clamp(0.0, mapHeightBudget)
          .toDouble();
      waterCardHeight = bounded(
        usableHeight * landscapePhoneWaterHeightFactor,
        landscapePhoneMinimumWaterHeight,
        landscapePhoneMaximumWaterHeight,
      );
      weatherCardHeight = bounded(
        usableHeight * landscapePhoneWeatherHeightFactor,
        landscapePhoneMinimumWeatherHeight,
        landscapePhoneMaximumWeatherHeight,
      );
      standardSectionHeight = bounded(
        usableHeight * landscapePhoneStandardSectionHeightFactor,
        landscapePhoneMinimumStandardSectionHeight,
        landscapePhoneMaximumStandardSectionHeight,
      );
      recentCatchesHeight = bounded(
        usableHeight * landscapePhoneRecentCatchesHeightFactor,
        landscapePhoneMinimumRecentCatchesHeight,
        landscapePhoneMaximumRecentCatchesHeight,
      );
    } else if (isLandscape) {
      sectionGap = bounded(usableHeight * .012, 4, 8);
      headerHeight = bounded(usableHeight * .12, 52, 72);
      bottomNavHeight = resolveBottomNavigationHeight(
        bounded(usableHeight * .14, 58, 68),
      );
      final firstHomeViewportHeight = bounded(
        usableHeight - (bottomNavigationOverlaysBody ? bottomNavHeight : 0),
        0,
        usableHeight,
      );
      heroMapHeight = bounded(firstHomeViewportHeight * .34, 220, 320);
      waterCardHeight = bounded(usableHeight * .24, 156, 184);
      weatherCardHeight = bounded(waterCardHeight * .72, 116, 136);
      standardSectionHeight = bounded(usableHeight * .30, 140, 172);
      recentCatchesHeight = bounded(usableHeight * .40, 170, 220);
    } else {
      sectionGap = bounded(
        shortestSide * (isTablet ? .016 : .018),
        isTablet ? 10 : 6,
        isTablet ? 14 : 8,
      );
      headerHeight = bounded(
        usableHeight * .085,
        isTablet ? 72 : 64,
        isTablet ? 96 : 82,
      );
      bottomNavHeight = resolveBottomNavigationHeight(
        bounded(usableHeight * .072, isTablet ? 64 : 58, isTablet ? 72 : 64),
      );
      final firstHomeViewportHeight = bounded(
        usableHeight - (bottomNavigationOverlaysBody ? bottomNavHeight : 0),
        0,
        usableHeight,
      );
      final portraitMapHeightFactor = isTablet
          ? .42
          : (isSmallPhone ? .38 : .40);
      heroMapHeight = bounded(
        firstHomeViewportHeight * portraitMapHeightFactor,
        isTablet ? 320 : (isSmallPhone ? 220 : 250),
        isTablet ? 480 : 390,
      );
      if (isTablet) {
        waterCardHeight = bounded(usableHeight * .19, 176, 204);
        weatherCardHeight = bounded(waterCardHeight * .66, 120, 138);
      } else {
        final waterMinimum = isSmallPhone
            ? 158.0
            : (isNormalPhone ? 166.0 : 172.0);
        final waterMaximum = isSmallPhone
            ? 170.0
            : (isNormalPhone ? 180.0 : 186.0);
        final weatherMinimum = isSmallPhone
            ? 112.0
            : (isNormalPhone ? 116.0 : 118.0);
        final weatherMaximum = isSmallPhone
            ? 122.0
            : (isNormalPhone ? 126.0 : 130.0);
        waterCardHeight = bounded(
          usableHeight * .205,
          waterMinimum,
          waterMaximum,
        );
        weatherCardHeight = bounded(
          waterCardHeight * .70,
          weatherMinimum,
          weatherMaximum,
        );
      }
      standardSectionHeight = bounded(
        usableHeight * (isTablet ? .16 : .18),
        isTablet ? 152 : 138,
        isTablet ? 188 : 164,
      );
      recentCatchesHeight = bounded(
        usableHeight * .22,
        isTablet ? 190 : (isSmallPhone ? 168 : 176),
        isTablet ? 246 : 220,
      );
    }

    final scrollClearance = bottomNavigationOverlaysBody
        ? sectionGap + bottomNavHeight + systemSafeArea.bottom
        : (isLandscapePhone ? 0.0 : sectionGap);
    final bottomContentClearance = scrollClearance;

    // Transitional compatibility for the current two-row dashboard. These
    // aliases can be removed after its staged migration to vertical sections.
    final dashboardCardHeight = standardSectionHeight;
    final dashboardAreaHeight =
        (dashboardCardHeight * 2) + recentCatchesHeight + (sectionGap * 2);
    final bottomSafeClearance = bottomContentClearance;

    return HomePremiumLayout._(
      bodyViewportSize: bodyViewportSize,
      systemSafeArea: systemSafeArea,
      bottomNavigationOverlaysBody: bottomNavigationOverlaysBody,
      isPortrait: isPortrait,
      isLandscape: isLandscape,
      isLandscapePhone: isLandscapePhone,
      isSmallPhone: isSmallPhone,
      isNormalPhone: isNormalPhone,
      isLargePhone: isLargePhone,
      isTablet: isTablet,
      horizontalPadding: horizontalPadding,
      sectionGap: sectionGap,
      usableHeight: usableHeight,
      headerHeight: headerHeight,
      heroMapHeight: heroMapHeight,
      waterCardHeight: waterCardHeight,
      weatherCardHeight: weatherCardHeight,
      standardSectionHeight: standardSectionHeight,
      recentCatchesHeight: recentCatchesHeight,
      bottomNavHeight: bottomNavHeight,
      scrollClearance: scrollClearance,
      bottomContentClearance: bottomContentClearance,
      dashboardAreaHeight: dashboardAreaHeight,
      dashboardCardHeight: dashboardCardHeight,
      bottomSafeClearance: bottomSafeClearance,
      titleFontScale: titleFontScale,
      bodyFontScale: bodyFontScale,
      iconScale: iconScale,
    );
  }

  static double _nonNegativeFinite(double value) {
    if (!value.isFinite || value <= 0) {
      return 0;
    }
    return value;
  }

  final Size bodyViewportSize;
  final EdgeInsets systemSafeArea;
  final bool bottomNavigationOverlaysBody;
  final bool isPortrait;
  final bool isLandscape;
  final bool isLandscapePhone;
  final bool isSmallPhone;
  final bool isNormalPhone;
  final bool isLargePhone;
  final bool isTablet;
  final double horizontalPadding;
  final double sectionGap;
  final double usableHeight;
  final double headerHeight;
  final double heroMapHeight;
  final double waterCardHeight;
  final double weatherCardHeight;
  final double standardSectionHeight;
  final double recentCatchesHeight;
  final double bottomNavHeight;
  final double scrollClearance;
  final double bottomContentClearance;

  // Transitional compatibility fields for staged Home migration.
  final double dashboardAreaHeight;
  final double dashboardCardHeight;
  final double bottomSafeClearance;
  final double titleFontScale;
  final double bodyFontScale;
  final double iconScale;
}
