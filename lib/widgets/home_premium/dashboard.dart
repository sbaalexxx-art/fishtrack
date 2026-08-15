import 'package:flutter/material.dart';

import '../../models/station.dart';
import '../../screens/weather_page.dart';
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
    required this.onWeatherMetricPressed,
    required this.onCommunityPressed,
    required this.onAiPressed,
  });

  final HomePremiumLayout layout;
  final ValueChanged<Station> onWaterLevelPressed;
  final VoidCallback onWeatherPressed;
  final ValueChanged<WeatherPageSection> onWeatherMetricPressed;
  final VoidCallback onCommunityPressed;
  final VoidCallback onAiPressed;

  static double primaryViewportHeightFor(HomePremiumLayout layout) =>
      _DashboardGeometry.from(layout).primaryViewportHeight;

  static double sectionSpacingFor(HomePremiumLayout layout) =>
      _DashboardGeometry.from(layout).spacing;

  Widget _action({required VoidCallback onTap, required Widget child}) {
    return Semantics(
      button: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _DashboardGeometry.from(layout);
    final spacing = geometry.spacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stackPairedCards =
            constraints.maxWidth < 360 || textScale >= 1.25;
        final pairedCardHeight =
            geometry.standardHeight +
            (stackPairedCards && textScale >= 1.25 ? 10 : 0);
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
              child: WaterLevelCardPremium(
                layout: layout,
                onOpenDetails: onWaterLevelPressed,
              ),
            ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              height: geometry.weatherHeight,
              child: _action(
                onTap: onWeatherPressed,
                child: WeatherCardPremium(
                  layout: layout,
                  onMetricPressed: onWeatherMetricPressed,
                ),
              ),
            ),
            SizedBox(height: spacing),
            if (stackPairedCards) ...[
              SizedBox(
                width: double.infinity,
                height: pairedCardHeight,
                child: aiCard,
              ),
              SizedBox(height: spacing),
              SizedBox(
                width: double.infinity,
                height: pairedCardHeight,
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
            SizedBox(height: geometry.recentSpacing),
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
    required this.recentSpacing,
    required this.waterHeight,
    required this.weatherHeight,
    required this.standardHeight,
  });

  factory _DashboardGeometry.from(HomePremiumLayout layout) {
    return _DashboardGeometry(
      spacing: layout.sectionGap.clamp(6.0, 7.0).toDouble(),
      recentSpacing: layout.sectionGap.clamp(6.0, 8.0).toDouble(),
      waterHeight: layout.waterCardHeight,
      weatherHeight: layout.weatherCardHeight,
      standardHeight: layout.standardSectionHeight,
    );
  }

  final double spacing;
  final double recentSpacing;
  final double waterHeight;
  final double weatherHeight;
  final double standardHeight;

  double get primaryViewportHeight =>
      waterHeight + weatherHeight + standardHeight + (spacing * 2);
}
