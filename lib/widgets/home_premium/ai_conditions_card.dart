import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../models/station.dart';
import '../../services/fishing_score_service.dart';
import '../../services/water_service.dart';
import 'home_premium_layout.dart';

enum FishingRating { excellent, good, fair, poor }

class AIConditionsCardPremium extends StatefulWidget {
  const AIConditionsCardPremium({super.key});

  @override
  State<AIConditionsCardPremium> createState() =>
      _AIConditionsCardPremiumState();
}

class _AIConditionsCardPremiumState extends State<AIConditionsCardPremium> {
  final FishingScoreService _scoreService = FishingScoreService();
  final WaterService _waterService = WaterService();
  late Future<FishingScoreResult> _scoreFuture;
  StreamSubscription<Station>? _stationSubscription;

  @override
  void initState() {
    super.initState();
    _scoreFuture = _scoreService.calculate();
    _stationSubscription = _waterService.stationSelections.listen((station) {
      if (mounted) {
        setState(
          () =>
              _scoreFuture = _scoreService.calculate(fallbackStation: station),
        );
      }
    });
  }

  @override
  void dispose() {
    _stationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FishingScoreResult>(
      future: _scoreFuture,
      builder: (context, snapshot) {
        final result = snapshot.data;
        final rating = _rating(result?.rating);
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: _AIConditionsCardView(
            score: result?.score,
            rating: rating,
            recommendation: snapshot.hasError
                ? 'No data available yet'
                : result?.recommendation ?? 'Calculating...',
            bestTime: result?.bestTime ?? '--:--',
            confidence: result?.confidence,
            isLoading: isLoading,
          ),
        );
      },
    );
  }

  FishingRating _rating(FishingScoreRating? rating) => switch (rating) {
    FishingScoreRating.excellent => FishingRating.excellent,
    FishingScoreRating.good => FishingRating.good,
    FishingScoreRating.fair => FishingRating.fair,
    FishingScoreRating.poor || null => FishingRating.poor,
  };
}

class _AIConditionsCardView extends StatelessWidget {
  const _AIConditionsCardView({
    required this.score,
    required this.rating,
    required this.recommendation,
    required this.bestTime,
    required this.confidence,
    required this.isLoading,
  });

  final double? score;
  final FishingRating rating;
  final String recommendation;
  final String bestTime;
  final int? confidence;
  final bool isLoading;

  Color get _color => switch (rating) {
    FishingRating.excellent => const Color(0xFF4CAF50),
    FishingRating.good => const Color(0xFF8BC34A),
    FishingRating.fair => const Color(0xFFFFB300),
    FishingRating.poor => const Color(0xFFE53935),
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
                          score == null ? '--/100' : '${score!.round()}/100',
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
                          recommendation,
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
                            value: score == null
                                ? (isLoading ? 0 : null)
                                : (score! / 100).clamp(0, 1),
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
                      confidence == null
                          ? 'Best: $bestTime'
                          : 'Best: $bestTime • $confidence%',
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

/// A restrained loading sheen that keeps its child's exact constraints.
class PremiumLoadingShimmer extends StatefulWidget {
  const PremiumLoadingShimmer({
    super.key,
    required this.isLoading,
    required this.child,
    this.borderRadius = 16,
  });

  final bool isLoading;
  final Widget child;
  final double borderRadius;

  @override
  State<PremiumLoadingShimmer> createState() => _PremiumLoadingShimmerState();
}

class _PremiumLoadingShimmerState extends State<PremiumLoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isLoading) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PremiumLoadingShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading == oldWidget.isLoading) return;
    if (widget.isLoading) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) return widget.child;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Opacity(opacity: .58, child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => FractionalTranslation(
                  translation: Offset((_controller.value * 2.6) - 1.3, 0),
                  child: child,
                ),
                child: const FractionallySizedBox(
                  widthFactor: .42,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Color(0x18FFFFFF),
                          Color(0x30FFFFFF),
                          Color(0x18FFFFFF),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
