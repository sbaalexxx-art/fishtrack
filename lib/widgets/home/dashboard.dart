import 'package:flutter/material.dart';

import 'water_level_card.dart';
import 'weather_card.dart';
import 'community_card.dart';
import 'ai_insights_card.dart';
import 'recent_catches_card.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          WaterLevelCard(),
          SizedBox(height: 16),

          WeatherCard(),
          SizedBox(height: 16),

          CommunityCard(),
          SizedBox(height: 16),

          AIFishingInsightsCard(),
          SizedBox(height: 16),

          RecentCatchesCard(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}
