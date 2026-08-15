import 'package:flutter/material.dart';

class AppDimensions {
  AppDimensions._();

  // Screen

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  // Device Types

  static bool isCompact(BuildContext context) => screenWidth(context) < 380;

  static bool isPhone(BuildContext context) => screenWidth(context) < 600;

  static bool isWide(BuildContext context) =>
      screenWidth(context) >= 600 && screenWidth(context) < 840;

  static bool isTablet(BuildContext context) => screenWidth(context) >= 840;

  static bool isCompactLandscape(BuildContext context) =>
      screenHeight(context) < 480;

  static bool isLargePhone(BuildContext context) =>
      screenHeight(context) >= 850;

  static bool isSmallPhone(BuildContext context) => screenHeight(context) < 750;

  // Home Layout

  static double mapHeight(BuildContext context) {
    if (isTablet(context)) {
      return 360;
    }

    if (isLargePhone(context)) {
      return 310;
    }

    if (isSmallPhone(context)) {
      return 240;
    }

    return 280;
  }

  // Design System

  static const double compactCardPadding = 14.0;

  static const double compactSpacing = 12.0;

  static const double sectionSpacing = 16.0;

  static const double borderRadius = 20.0;

  static const double bottomNavigationHeight = 72.0;

  static const double minimumTouchTarget = 48.0;
  static const double mapControlVisualSize = 42.0;
  static const double contentMaxWidth = 1180.0;
}
