import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';

enum FishingRating { excellent, good, fair, poor }

class AIConditionsCardPremium extends StatelessWidget {
  const AIConditionsCardPremium({
    super.key,
    this.score = 8.6,
    this.rating = FishingRating.excellent,
    this.bestTime = '06:00 - 10:00',
  });

  final double score;
  final FishingRating rating;
  final String bestTime;

  Color get _color {
    switch (rating) {
      case FishingRating.excellent:
        return const Color(0xFF4CAF50);
      case FishingRating.good:
        return const Color(0xFF8BC34A);
      case FishingRating.fair:
        return const Color(0xFFFFB300);
      case FishingRating.poor:
        return const Color(0xFFE53935);
    }
  }

  String get _label {
    switch (rating) {
      case FishingRating.excellent:
        return "Excellent";
      case FishingRating.good:
        return "Good";
      case FishingRating.fair:
        return "Fair";
      case FishingRating.poor:
        return "Poor";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 185,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2335),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_alt_rounded,
                color: Color(0xFF42A5F5),
                size: 20,
              ),

              const SizedBox(width: 8),

              Text(
                "Fishing AI",
                style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${score.toStringAsFixed(1)}/10",
                      style: const TextStyle(
                        fontSize: 30,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _label,
                      style: TextStyle(
                        color: _color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: 74,
                height: 74,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 74,
                      height: 74,
                      child: CircularProgressIndicator(
                        value: score / 10,
                        strokeWidth: 6,
                        backgroundColor: Colors.white10,
                        color: _color,
                      ),
                    ),
                    Icon(Icons.phishing, color: _color, size: 30),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          Row(
            children: [
              const Icon(Icons.schedule, size: 15, color: Colors.white54),
              const SizedBox(width: 5),
              Text("Best: $bestTime", style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }
}
