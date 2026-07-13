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
    required this.onWaterLevelPressed,
    required this.onWeatherPressed,
    required this.onCommunityPressed,
    required this.onAiPressed,
  });

  final VoidCallback onWaterLevelPressed;
  final VoidCallback onWeatherPressed;
  final VoidCallback onCommunityPressed;
  final VoidCallback onAiPressed;

  Widget _action({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final spacing = layout.sectionGap;

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
              height: layout.waterCardHeight,
              child: _action(
                onTap: onWaterLevelPressed,
                child: const WaterLevelCardPremium(),
              ),
            ),
            SizedBox(height: spacing),
            SizedBox(
              width: double.infinity,
              height: layout.weatherCardHeight,
              child: _action(
                onTap: onWeatherPressed,
                child: const WeatherCardPremium(),
              ),
            ),
            SizedBox(height: spacing),
            if (stackPairedCards) ...[
              SizedBox(
                width: double.infinity,
                height: layout.standardSectionHeight,
                child: aiCard,
              ),
              SizedBox(height: spacing),
              SizedBox(
                width: double.infinity,
                height: layout.standardSectionHeight,
                child: communityCard,
              ),
            ] else
              SizedBox(
                width: double.infinity,
                height: layout.standardSectionHeight,
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
