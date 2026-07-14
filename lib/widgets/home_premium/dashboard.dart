import 'package:flutter/material.dart';

import 'ai_conditions_card.dart';
import 'community_card.dart';
import 'home_premium_layout.dart';
import 'recent_catches_card.dart';
import 'water_level_card.dart';
import 'weather_card.dart';

class PremiumDashboard extends StatelessWidget {
  const PremiumDashboard({
    super.key,
    required this.layout,
    required this.onWaterLevelPressed,
    required this.onWeatherPressed,
    required this.onCommunityPressed,
    required this.onAiPressed,
  });

  final HomePremiumLayout layout;
  final VoidCallback onWaterLevelPressed;
  final VoidCallback onWeatherPressed;
  final VoidCallback onCommunityPressed;
  final VoidCallback onAiPressed;

  static double primaryViewportHeightFor(HomePremiumLayout layout) =>
      _DashboardGeometry.from(layout).primaryViewportHeight;

  static double sectionSpacingFor(HomePremiumLayout layout) =>
      _DashboardGeometry.from(layout).spacing;

  Widget _action({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _DashboardGeometry.from(layout);
    final spacing = geometry.spacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        const minimumPairedCardsWidth = 420.0;
        final stackPairedCards =
            layout.isLandscapePhone &&
            constraints.maxWidth < minimumPairedCardsWidth;
        final aiCard = _action(
          onTap: onAiPressed,
          child: const AIConditionsCardPremium(),
        );
        final communityCard = _action(
          onTap: onCommunityPressed,
          child: const CommunityCardPremium(),
        );

        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: geometry.waterHeight,
              child: _action(
                onTap: onWaterLevelPressed,
                child: WaterLevelCardPremium(layout: layout),
              ),
            ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              height: geometry.weatherHeight,
              child: _action(
                onTap: onWeatherPressed,
                child: WeatherCardPremium(layout: layout),
              ),
            ),
            SizedBox(height: spacing),
            if (stackPairedCards) ...[
              SizedBox(
                width: double.infinity,
                height: geometry.standardHeight,
                child: aiCard,
              ),
              SizedBox(height: spacing),
              SizedBox(
                width: double.infinity,
                height: geometry.standardHeight,
                child: communityCard,
              ),
            ] else
              SizedBox(
                width: double.infinity,
                height: geometry.standardHeight,
                child: Row(
                  children: [
                    Expanded(child: aiCard),
                    SizedBox(width: spacing),
                    Expanded(child: communityCard),
                  ],
                ),
              ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              height: layout.recentCatchesHeight,
              child: const RecentCatchesCardPremium(),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardGeometry {
  const _DashboardGeometry({
    required this.spacing,
    required this.waterHeight,
    required this.weatherHeight,
    required this.standardHeight,
  });

  factory _DashboardGeometry.from(HomePremiumLayout layout) {
    final compactFirstViewport = layout.isPortrait && !layout.isTablet;
    if (!compactFirstViewport) {
      return _DashboardGeometry(
        spacing: layout.sectionGap * .78,
        waterHeight: layout.waterCardHeight * .94,
        weatherHeight: layout.weatherCardHeight * .88,
        standardHeight: layout.standardSectionHeight,
      );
    }

    return _DashboardGeometry(
      spacing: (layout.sectionGap * .55).clamp(4.0, 7.0).toDouble(),
      waterHeight: (layout.waterCardHeight * .86)
          .clamp(100.0, 112.0)
          .toDouble(),
      weatherHeight: (layout.weatherCardHeight * .84)
          .clamp(104.0, 108.0)
          .toDouble(),
      standardHeight: (layout.standardSectionHeight * .98)
          .clamp(146.0, 152.0)
          .toDouble(),
    );
  }

  final double spacing;
  final double waterHeight;
  final double weatherHeight;
  final double standardHeight;

  double get primaryViewportHeight =>
      waterHeight + weatherHeight + standardHeight + (spacing * 2);
}
