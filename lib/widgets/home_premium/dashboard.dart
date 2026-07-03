import 'package:flutter/material.dart';

import 'ai_conditions_card.dart';
import 'community_card.dart';
import 'recent_catches_card.dart';
import 'water_level_card.dart';
import 'weather_card.dart';

class PremiumDashboard extends StatelessWidget {
  const PremiumDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool desktop = width >= 1200;
    final bool tablet = width >= 700;

    if (desktop) {
      return Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: WaterLevelCardPremium()),
              SizedBox(width: 16),
              Expanded(child: WeatherCardPremium()),
              SizedBox(width: 16),
              Expanded(child: AIConditionsCardPremium()),
              SizedBox(width: 16),
              Expanded(child: CommunityCardPremium()),
            ],
          ),
          SizedBox(height: 18),
          RecentCatchesCardPremium(),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: const [
            Expanded(child: WaterLevelCardPremium()),
            SizedBox(width: 12),
            Expanded(child: WeatherCardPremium()),
          ],
        ),

        SizedBox(height: 12),

        Row(
          children: const [
            Expanded(child: CommunityCardPremium()),
            SizedBox(width: 12),
            Expanded(child: AIConditionsCardPremium()),
          ],
        ),

        SizedBox(height: 14),

        const RecentCatchesCardPremium(),
      ],
    );
  }
}
