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
    final isRomanian = Localizations.localeOf(context).languageCode == 'ro';
    final result = _visibleResult;
    return PremiumLoadingShimmer(
      isLoading: _isLoading,
      child: _AIConditionsCardView(
        score: result?.score,
        rating: _rating(result?.rating),
        recommendation: _localizedStatus(
          result?.recommendation ?? 'Calculating...',
          isRomanian,
        ),
        bestTime: result?.bestTime ?? '--:--',
        confidence: result?.confidence,
        isLoading: _isLoading,
      ),
    );
  }

  FishingRating _rating(FishingScoreRating? rating) => switch (rating) {
    FishingScoreRating.excellent => FishingRating.excellent,
    FishingScoreRating.good => FishingRating.good,
    FishingScoreRating.fair => FishingRating.fair,
    FishingScoreRating.poor || null => FishingRating.poor,
  };

  String _localizedStatus(String value, bool isRomanian) {
    if (!isRomanian) return value;
    return switch (value) {
      'Excellent' => 'Excelent',
      'Good' => 'Bun',
      'Fair' => 'Acceptabil',
      'Poor' => 'Slab',
      'Calculating...' => 'Se calculează...',
      _ => value,
    };
  }
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
        final isRomanian = Localizations.localeOf(context).languageCode == 'ro';
        final localizedBestTime = isRomanian
            ? bestTime.replaceAll(' or ', ' sau ')
            : bestTime;
        final layout = HomePremiumLayout.of(context);
        final compact = constraints.maxWidth < 220;
        final denseHeight = constraints.maxHeight < 145;
        final dense = compact || layout.isLandscapePhone || denseHeight;
        final gaugeSize = (dense ? 48.0 : 58.0) * layout.iconScale;

        return Container(
          padding: EdgeInsets.all(
            layout.isLandscapePhone
                ? 7
                : layout.isSmallPhone
                ? 8
                : (layout.isTablet ? 12 : 10),
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
                    size: (dense ? 18 : 20) * layout.iconScale,
                  ),
                  SizedBox(width: dense ? 5 : 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        isRomanian ? 'Indice FluviAI' : 'FluviAI Fishing Index',
                        maxLines: 1,
                        style: AppTextStyles.cardTitle.copyWith(
                          fontSize: (dense ? 14 : 16) * layout.titleFontScale,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 4 : 6),
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
                            fontSize: (dense ? 23 : 29) * layout.titleFontScale,
                            height: 1,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: dense ? 2 : 4),
                        Text(
                          recommendation,
                          maxLines: 2,
                          style: TextStyle(
                            color: _color,
                            fontSize: dense ? 12 : 14,
                            height: 1.05,
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
                            strokeWidth: dense ? 5 : 6,
                            backgroundColor: Colors.white10,
                            color: _color,
                          ),
                        ),
                        Icon(
                          Icons.phishing,
                          color: _color,
                          size: dense ? 23 : 28,
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
                          ? '${isRomanian ? 'Cel mai favorabil:' : 'Best:'} $localizedBestTime'
                          : '${isRomanian ? 'Cel mai favorabil:' : 'Best:'} $localizedBestTime • $confidence%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: dense ? 11 : 13,
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
