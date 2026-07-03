import 'package:flutter/material.dart';

import 'ai_insights_card.dart';
import 'community_card.dart';
import 'recent_catches_card.dart';
import 'water_level_card.dart';
import 'weather_card.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: WaterLevelCard()),
              SizedBox(width: spacing),
              Expanded(child: WeatherCard()),
            ],
          ),

          const SizedBox(height: spacing),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: CommunityCard()),
              SizedBox(width: spacing),
              Expanded(child: AIFishingInsightsCard()),
            ],
          ),

          const SizedBox(height: spacing),

          const RecentCatchesCard(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
