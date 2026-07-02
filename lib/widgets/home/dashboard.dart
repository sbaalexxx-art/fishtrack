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
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double spacing = 12;

          // Înălțimea disponibilă pentru cele 2 rânduri + Recent Catches
          final double recentHeight = 150;
          final double available =
              constraints.maxHeight - recentHeight - (spacing * 2);

          final double cardHeight = available / 2;

          return Column(
            children: [
              SizedBox(
                height: cardHeight,
                child: Row(
                  children: [
                    Expanded(child: WaterLevelCard()),
                    SizedBox(width: spacing),
                    Expanded(child: WeatherCard()),
                  ],
                ),
              ),

              SizedBox(height: spacing),

              SizedBox(
                height: cardHeight,
                child: Row(
                  children: [
                    Expanded(child: CommunityCard()),
                    SizedBox(width: spacing),
                    Expanded(child: AIFishingInsightsCard()),
                  ],
                ),
              ),

              SizedBox(height: spacing),

              const SizedBox(height: 150, child: RecentCatchesCard()),
            ],
          );
        },
      ),
    );
  }
}
