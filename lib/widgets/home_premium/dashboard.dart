import 'package:flutter/material.dart';

import 'ai_conditions_card.dart';
import 'community_card.dart';
import 'home_premium_layout.dart';
import 'recent_catches_card.dart';
import 'water_level_card.dart';
import 'weather_card.dart';

class PremiumDashboard extends StatelessWidget {
  const PremiumDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final spacing = layout.sectionGap;

    return Column(
      children: [
        SizedBox(
          height: layout.dashboardCardHeight,
          child: Row(
            children: [
              const Expanded(child: WaterLevelCardPremium()),
              SizedBox(width: spacing),
              const Expanded(child: WeatherCardPremium()),
            ],
          ),
        ),
        SizedBox(height: spacing),
        SizedBox(
          height: layout.dashboardCardHeight,
          child: Row(
            children: [
              const Expanded(child: CommunityCardPremium()),
              SizedBox(width: spacing),
              const Expanded(child: AIConditionsCardPremium()),
            ],
          ),
        ),
        SizedBox(height: spacing),
        const RecentCatchesCardPremium(),
      ],
    );
  }
}
