import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
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
  FishingScoreResult? _visibleResult;
  Station? _selectedStation;
  String _scoreKey = 'nearest';
  String? _refreshingKey;
  bool _isLoading = true;
  StreamSubscription<Station>? _stationSubscription;

  @override
  void initState() {
    super.initState();
    _visibleResult = _scoreService.cachedResult();
    _isLoading = _visibleResult == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshScore();
    });
    _stationSubscription = _waterService.stationSelections.listen((station) {
      if (!mounted) return;
      _selectedStation = station;
      _refreshScore();
    });
  }

  void _refreshScore() {
    final station = _selectedStation;
    final key = station?.id ?? 'nearest';
    if (_refreshingKey == key) return;

    final cached = _scoreService.cachedResult(fallbackStation: station);
    setState(() {
      _scoreKey = key;
      _visibleResult = cached;
      _isLoading = cached == null;
      _refreshingKey = key;
    });

    _scoreService
        .calculate(fallbackStation: station)
        .then((result) {
          if (!mounted || _scoreKey != key) return;
          setState(() {
            if (result.hasEnoughData || _visibleResult == null) {
              _visibleResult = result;
            }
            _isLoading = false;
            if (_refreshingKey == key) _refreshingKey = null;
          });
        })
        .onError((Object _, StackTrace _) {
          if (!mounted || _scoreKey != key) return;
          setState(() {
            _isLoading = false;
            if (_refreshingKey == key) _refreshingKey = null;
          });
        });
  }

  @override
  void dispose() {
    _stationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _visibleResult;
    final l10n = context.l10n;
    final recommendation = switch (result?.recommendation) {
      null => _isLoading ? l10n.loading : l10n.notEnoughData,
      'Excellent' => l10n.scoreExcellent,
      'Good' => l10n.scoreGood,
      'Fair' => l10n.scoreFair,
      'Poor' => l10n.scorePoor,
      'Not enough data yet' => l10n.notEnoughData,
      final value => value,
    };

    return PremiumLoadingShimmer(
      isLoading: _isLoading,
      child: _AIConditionsCardView(
        score: result?.score,
        rating: _rating(result?.rating),
        recommendation: recommendation,
        bestTime: result?.bestTime ?? '--:--',
        confidence: result?.confidence,
      ),
    );
  }

  FishingRating? _rating(FishingScoreRating? rating) => switch (rating) {
    FishingScoreRating.excellent => FishingRating.excellent,
    FishingScoreRating.good => FishingRating.good,
    FishingScoreRating.fair => FishingRating.fair,
    FishingScoreRating.poor => FishingRating.poor,
    null => null,
  };
}

class _AIConditionsCardView extends StatelessWidget {
  const _AIConditionsCardView({
    required this.score,
    required this.rating,
    required this.recommendation,
    required this.bestTime,
    required this.confidence,
  });

  final double? score;
  final FishingRating? rating;
  final String recommendation;
  final String bestTime;
  final int? confidence;

  Color get _color => switch (rating) {
    FishingRating.excellent => const Color(0xFF4CAF50),
    FishingRating.good => const Color(0xFF8BC34A),
    FishingRating.fair => const Color(0xFFFFB300),
    FishingRating.poor => const Color(0xFFE53935),
    null => const Color(0xFF9AA7B2),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const accent = Color(0xFF42A5F5);
        final l10n = context.l10n;
        final localizedBestTime = bestTime.replaceAll(' or ', ' ${l10n.or} ');
        final layout = HomePremiumLayout.of(context);
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compactWidth = constraints.maxWidth < 230;
        final constrainedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight < 158;
        final dense =
            compactWidth ||
            layout.isLandscapePhone ||
            constrainedHeight ||
            textScale >= 1.25;
        final showSubtitle =
            !dense &&
            (!constraints.hasBoundedHeight || constraints.maxHeight >= 166);
        final gaugeSize = (dense ? 44.0 : 52.0) * layout.iconScale;
        final cardPadding = dense
            ? 8.0
            : layout.isTablet
            ? 12.0
            : 10.0;

        return Container(
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF142632), Color(0xFF0B1B25)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: dense ? 24 : 27,
                    height: dense ? 24 : 27,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.psychology_alt_rounded,
                      color: accent,
                      size: (dense ? 16 : 18) * layout.iconScale,
                    ),
                  ),
                  SizedBox(width: dense ? 6 : 8),
                  Expanded(
                    child: Text(
                      l10n.fishingInsights,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle.copyWith(
                        fontSize: (dense ? 13.5 : 15) * layout.titleFontScale,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
              if (showSubtitle) ...[
                const SizedBox(height: 3),
                Text(
                  l10n.fluviScoreSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10.5 * layout.bodyFontScale,
                    height: 1,
                  ),
                ),
              ],
              SizedBox(height: dense ? 4 : 6),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              text: score == null
                                  ? '--'
                                  : score!.round().toString(),
                              children: [
                                TextSpan(
                                  text: '/100',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize:
                                        (dense ? 11 : 12) *
                                        layout.bodyFontScale,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize:
                                  (dense ? 25 : 29) * layout.titleFontScale,
                              height: 1,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: dense ? 2 : 3),
                          Text(
                            recommendation,
                            maxLines: dense ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _color,
                              fontSize:
                                  (dense ? 11.5 : 13) * layout.bodyFontScale,
                              height: 1.05,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: dense ? 6 : 8),
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
                                  ? 0
                                  : (score! / 100).clamp(0, 1),
                              strokeWidth: dense ? 4 : 5,
                              strokeCap: StrokeCap.round,
                              backgroundColor: Colors.white10,
                              color: _color,
                            ),
                          ),
                          Icon(
                            Icons.phishing,
                            color: _color,
                            size: dense ? 20 : 23,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: dense ? 4 : 6),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 6 : 8,
                  vertical: dense ? 4 : 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: '${l10n.bestTimeWindow}: ',
                          children: [
                            TextSpan(
                              text: localizedBestTime,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        maxLines: textScale >= 1.25 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          fontSize:
                              (dense ? 10.5 : 11.5) * layout.bodyFontScale,
                          height: 1.08,
                        ),
                      ),
                    ),
                    if (confidence != null) ...[
                      const SizedBox(width: 5),
                      Semantics(
                        label: l10n.confidence(confidence!),
                        child: Text(
                          '$confidence%',
                          style: TextStyle(
                            color: accent,
                            fontSize:
                                (dense ? 10.5 : 11.5) * layout.bodyFontScale,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
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
