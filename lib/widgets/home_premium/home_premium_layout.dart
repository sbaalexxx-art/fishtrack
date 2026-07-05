import 'package:flutter/material.dart';

class HomePremiumLayout {
  const HomePremiumLayout._({
    required this.isSmallPhone,
    required this.isNormalPhone,
    required this.isLargePhone,
    required this.isTablet,
    required this.horizontalPadding,
    required this.sectionGap,
    required this.usableHeight,
    required this.headerHeight,
    required this.heroMapHeight,
    required this.dashboardAreaHeight,
    required this.dashboardCardHeight,
    required this.recentCatchesHeight,
    required this.bottomNavHeight,
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
    final isSmallPhone = size.width <= 360;
    final isNormalPhone = size.width > 360 && size.width <= 430;
    final isLargePhone = size.width > 430 && size.width < 480;
    final isTablet = size.width >= 480;

    late final double horizontalPadding;
    final sectionGap = (usableHeight * .008).clamp(4.0, 10.0).toDouble();
    final headerHeight = usableHeight * .10;
    final heroMapHeight = usableHeight * .45;
    final dashboardAreaHeight = usableHeight * .55;
    final dashboardContentHeight = (dashboardAreaHeight - (sectionGap * 2))
        .clamp(0.0, double.infinity)
        .toDouble();
    final dashboardCardHeight = (dashboardContentHeight * .35)
        .clamp(132.0, double.infinity)
        .toDouble();
    final recentCatchesHeight = (dashboardContentHeight * .30)
        .clamp(112.0, double.infinity)
        .toDouble();
    final bottomNavHeight = (usableHeight * .072).clamp(58.0, 64.0).toDouble();
    late final double titleFontScale;
    late final double bodyFontScale;
    late final double iconScale;

    if (isSmallPhone) {
      horizontalPadding = 12;
      titleFontScale = .90;
      bodyFontScale = .90;
      iconScale = .90;
    } else if (isNormalPhone) {
      horizontalPadding = 14;
      titleFontScale = .95;
      bodyFontScale = .95;
      iconScale = .95;
    } else if (isLargePhone) {
      horizontalPadding = 16;
      titleFontScale = 1;
      bodyFontScale = 1;
      iconScale = 1;
    } else {
      horizontalPadding = 22;
      titleFontScale = 1.08;
      bodyFontScale = 1.05;
      iconScale = 1.10;
    }

    return HomePremiumLayout._(
      isSmallPhone: isSmallPhone,
      isNormalPhone: isNormalPhone,
      isLargePhone: isLargePhone,
      isTablet: isTablet,
      horizontalPadding: horizontalPadding,
      sectionGap: sectionGap,
      usableHeight: usableHeight,
      headerHeight: headerHeight,
      heroMapHeight: heroMapHeight,
      dashboardAreaHeight: dashboardAreaHeight,
      dashboardCardHeight: dashboardCardHeight,
      recentCatchesHeight: recentCatchesHeight,
      bottomNavHeight: bottomNavHeight,
      bottomSafeClearance: sectionGap + viewPadding.bottom,
      titleFontScale: titleFontScale,
      bodyFontScale: bodyFontScale,
      iconScale: iconScale,
    );
  }

  final bool isSmallPhone;
  final bool isNormalPhone;
  final bool isLargePhone;
  final bool isTablet;
  final double horizontalPadding;
  final double sectionGap;
  final double usableHeight;
  final double headerHeight;
  final double heroMapHeight;
  final double dashboardAreaHeight;
  final double dashboardCardHeight;
  final double recentCatchesHeight;
  final double bottomNavHeight;
  final double bottomSafeClearance;
  final double titleFontScale;
  final double bodyFontScale;
  final double iconScale;
}
