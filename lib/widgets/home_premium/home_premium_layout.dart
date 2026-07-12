import 'package:flutter/material.dart';

class HomePremiumLayout {
  const HomePremiumLayout._({
    required this.isPortrait,
    required this.isLandscape,
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
    required this.bottomContentClearance,
    required this.dashboardAreaHeight,
    required this.dashboardCardHeight,
    required this.bottomSafeClearance,
    required this.titleFontScale,
    required this.bodyFontScale,
    required this.iconScale,
  });

  factory HomePremiumLayout.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final usableHeight = (size.height - viewPadding.top - viewPadding.bottom)
        .clamp(0.0, double.infinity)
        .toDouble();
    final isLandscape = size.width > size.height;
    final isPortrait = !isLandscape;
    final shortestSide = size.shortestSide;
    final isTablet = shortestSide >= 600;
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

    if (isTablet) {
      horizontalPadding = bounded(
        shortestSide * .04,
        24,
        isLandscape ? 32 : 28,
      );
      titleFontScale = 1.08;
      bodyFontScale = 1.05;
      iconScale = 1.10;
    } else if (isLandscape) {
      horizontalPadding = bounded(shortestSide * .04, 14, 18);
      titleFontScale = .90;
      bodyFontScale = .90;
      iconScale = .90;
    } else if (isSmallPhone) {
      horizontalPadding = bounded(shortestSide * .035, 12, 14);
      titleFontScale = .90;
      bodyFontScale = .90;
      iconScale = .90;
    } else if (isNormalPhone) {
      horizontalPadding = bounded(shortestSide * .036, 14, 16);
      titleFontScale = .95;
      bodyFontScale = .95;
      iconScale = .95;
    } else if (isLargePhone) {
      horizontalPadding = bounded(shortestSide * .038, 16, 20);
      titleFontScale = 1;
      bodyFontScale = 1;
      iconScale = 1;
    }

    if (isLandscape) {
      sectionGap = bounded(usableHeight * .012, 4, 8);
      headerHeight = bounded(usableHeight * .12, 52, isTablet ? 72 : 64);
      bottomNavHeight = bounded(
        usableHeight * .14,
        isTablet ? 58 : 52,
        isTablet ? 68 : 58,
      );
      final firstHomeViewportHeight = bounded(
        usableHeight - bottomNavHeight,
        0,
        usableHeight,
      );
      heroMapHeight = bounded(
        firstHomeViewportHeight * (isTablet ? .34 : .36),
        isTablet ? 220 : 190,
        isTablet ? 320 : 260,
      );
      waterCardHeight = isTablet
          ? bounded(usableHeight * .20, 135, 160)
          : bounded(usableHeight * .30, 116, 130);
      weatherCardHeight = bounded(
        waterCardHeight * (isTablet ? .74 : .76),
        isTablet ? 132 : 120,
        isTablet ? 150 : 130,
      );
      standardSectionHeight = bounded(
        usableHeight * .36,
        132,
        isTablet ? 184 : 156,
      );
      recentCatchesHeight = bounded(
        usableHeight * .48,
        156,
        isTablet ? 240 : 210,
      );
    } else {
      sectionGap = bounded(
        shortestSide * (isTablet ? .02 : .027),
        isTablet ? 12 : 8,
        isTablet ? 16 : 12,
      );
      headerHeight = bounded(
        usableHeight * .085,
        isTablet ? 72 : 64,
        isTablet ? 96 : 82,
      );
      bottomNavHeight = bounded(
        usableHeight * .072,
        isTablet ? 64 : 58,
        isTablet ? 72 : 64,
      );
      final firstHomeViewportHeight = bounded(
        usableHeight - bottomNavHeight,
        0,
        usableHeight,
      );
      heroMapHeight = bounded(
        firstHomeViewportHeight * (isTablet ? .41 : .42),
        isTablet ? 320 : 250,
        isTablet ? 480 : 390,
      );
      if (isTablet) {
        waterCardHeight = bounded(usableHeight * .15, 145, 175);
        weatherCardHeight = bounded(waterCardHeight * .74, 145, 165);
      } else {
        final waterMinimum = isSmallPhone
            ? 116.0
            : (isNormalPhone ? 122.0 : 128.0);
        final waterMaximum = isSmallPhone
            ? 126.0
            : (isNormalPhone ? 134.0 : 140.0);
        final weatherMinimum = isSmallPhone
            ? 125.0
            : (isNormalPhone ? 128.0 : 132.0);
        final weatherMaximum = isSmallPhone
            ? 136.0
            : (isNormalPhone ? 142.0 : 150.0);
        waterCardHeight = bounded(
          usableHeight * .16,
          waterMinimum,
          waterMaximum,
        );
        weatherCardHeight = bounded(
          waterCardHeight * .74,
          weatherMinimum,
          weatherMaximum,
        );
      }
      standardSectionHeight = bounded(
        usableHeight * (isTablet ? .18 : .19),
        isTablet ? 172 : 140,
        isTablet ? 212 : 176,
      );
      recentCatchesHeight = bounded(
        usableHeight * .25,
        isTablet ? 220 : 180,
        isTablet ? 300 : 240,
      );
    }

    final bottomContentClearance =
        bottomNavHeight + viewPadding.bottom + sectionGap;

    // Transitional compatibility for the current two-row dashboard. These
    // aliases can be removed after its staged migration to vertical sections.
    final dashboardCardHeight = standardSectionHeight;
    final dashboardAreaHeight =
        (dashboardCardHeight * 2) + recentCatchesHeight + (sectionGap * 2);
    final bottomSafeClearance = bottomContentClearance;

    return HomePremiumLayout._(
      isPortrait: isPortrait,
      isLandscape: isLandscape,
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
      bottomContentClearance: bottomContentClearance,
      dashboardAreaHeight: dashboardAreaHeight,
      dashboardCardHeight: dashboardCardHeight,
      bottomSafeClearance: bottomSafeClearance,
      titleFontScale: titleFontScale,
      bodyFontScale: bodyFontScale,
      iconScale: iconScale,
    );
  }

  final bool isPortrait;
  final bool isLandscape;
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
  final double bottomContentClearance;

  // Transitional compatibility fields for staged Home migration.
  final double dashboardAreaHeight;
  final double dashboardCardHeight;
  final double bottomSafeClearance;
  final double titleFontScale;
  final double bodyFontScale;
  final double iconScale;
}
