import 'package:flutter/material.dart';

class AppDimensions {
  AppDimensions._();

  // Screen

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  // Device Types

  static bool isTablet(BuildContext context) => screenWidth(context) >= 700;

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
}
