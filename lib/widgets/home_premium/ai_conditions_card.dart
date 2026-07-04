import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import 'home_premium_layout.dart';

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

  Color get _color => switch (rating) {
    FishingRating.excellent => const Color(0xFF4CAF50),
    FishingRating.good => const Color(0xFF8BC34A),
    FishingRating.fair => const Color(0xFFFFB300),
    FishingRating.poor => const Color(0xFFE53935),
  };

  String get _label => switch (rating) {
    FishingRating.excellent => 'Excellent',
    FishingRating.good => 'Good',
    FishingRating.fair => 'Fair',
    FishingRating.poor => 'Poor',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = HomePremiumLayout.of(context);
        final compact = constraints.maxWidth < 180;
        final gaugeSize = (compact ? 48.0 : 58.0) * layout.iconScale;

        return Container(
          padding: EdgeInsets.all(
            layout.isSmallPhone ? 8 : (layout.isTablet ? 12 : 10),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2335),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology_alt_rounded,
                    color: Color(0xFF42A5F5),
                    size: 20 * layout.iconScale,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'FISHING AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(
                        fontSize: 16 * layout.titleFontScale,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${score.toStringAsFixed(1)}/10',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize:
                                (compact ? 23 : 29) * layout.titleFontScale,
                            height: 1,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _color,
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: gaugeSize,
                    height: gaugeSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.square(
                          dimension: gaugeSize,
                          child: CircularProgressIndicator(
                            value: (score / 10).clamp(0, 1),
                            strokeWidth: compact ? 5 : 6,
                            backgroundColor: Colors.white10,
                            color: _color,
                          ),
                        ),
                        Icon(
                          Icons.phishing,
                          color: _color,
                          size: compact ? 23 : 28,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: Colors.white54),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Best: $bestTime',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
