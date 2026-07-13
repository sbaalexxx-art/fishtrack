import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../models/water_level.dart';
import '../../services/water_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

class WaterLevelCardPremium extends StatefulWidget {
  const WaterLevelCardPremium({super.key, this.selectedStation});

  final Station? selectedStation;

  @override
  State<WaterLevelCardPremium> createState() => _WaterLevelCardPremiumState();
}

class _WaterLevelCardPremiumState extends State<WaterLevelCardPremium> {
  final WaterService _waterService = WaterService();
  late Future<Station?> _stationFuture;
  StreamSubscription<Station>? _selectionSubscription;
  WaterUiResult? _waterResult;
  String? _waterResultStationId;
  bool _isWaterResultLoading = false;
  int _stationRequestId = 0;

  @override
  void initState() {
    super.initState();
    _stationFuture = _loadStation(widget.selectedStation);
    _selectionSubscription = _waterService.stationSelections.listen((station) {
      if (mounted) {
        setState(() {
          _stationFuture = _loadStation(station);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant WaterLevelCardPremium oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedStation?.id != widget.selectedStation?.id) {
      _stationFuture = _loadStation(widget.selectedStation);
    }
  }

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    super.dispose();
  }

  Future<Station?> _loadStation(Station? fallbackStation) async {
    final requestId = ++_stationRequestId;
    _isWaterResultLoading = true;

    final station = await _waterService.getNearestStation(
      fallbackStation: fallbackStation,
    );
    if (requestId != _stationRequestId) return station;

    if (station == null) {
      if (mounted) setState(() => _isWaterResultLoading = false);
      return null;
    }

    unawaited(_loadWaterResult(station, requestId));
    return station;
  }

  Future<void> _loadWaterResult(Station station, int requestId) async {
    if (mounted && requestId == _stationRequestId) {
      setState(() {
        final hasCurrentResult =
            _waterResult != null && _waterResultStationId == station.id;
        if (!hasCurrentResult) _waterResult = null;
        _waterResultStationId = station.id;
        _isWaterResultLoading = true;
      });
    }

    late final WaterUiResult result;
    try {
      result = await _waterService.getWaterUiResult(station, limit: 72);
    } on Exception {
      result = const WaterUiResult(
        latestReading: null,
        history: [],
        source: null,
        sourceName: null,
        measurementTimestamp: null,
        dataAge: null,
        isStale: false,
        status: WaterUiStatus.providerError,
        safeDiagnosticMessage: 'Water UI request failed',
      );
    }

    if (!mounted ||
        requestId != _stationRequestId ||
        _waterResultStationId != station.id) {
      return;
    }

    setState(() {
      _waterResult = result;
      _isWaterResultLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Station?>(
      future: _stationFuture,
      builder: (context, snapshot) {
        final station = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final waterResult =
            station != null && _waterResultStationId == station.id
            ? _waterResult
            : null;
        final isInitialLoading =
            waterResult == null &&
            !snapshot.hasError &&
            (isLoading || _isWaterResultLoading);
        final latestReading = waterResult?.latestReading;
        final hasStationReading = station?.hasWaterLevel == true;
        final hasReading = latestReading != null || hasStationReading;
        final waterValue = latestReading?.value ?? station?.level;
        final waterUnit =
            latestReading?.unit ?? station?.waterLevelUnit ?? 'cm';
        final trend =
            latestReading?.trend ?? station?.trend ?? WaterTrend.stable;
        final hasKnownTrend =
            latestReading?.hasKnownTrend ??
            (hasStationReading && station!.hasKnownTrend);
        final measurementTimestamp =
            waterResult?.measurementTimestamp ??
            (hasStationReading ? station!.lastUpdate : null);
        final reliabilityStatus =
            waterResult?.status ??
            (hasReading
                ? WaterUiStatus.insufficientHistory
                : WaterUiStatus.unavailable);
        final stationName =
            station?.name ??
            (snapshot.hasError
                ? Localizations.localeOf(context).languageCode == 'ro'
                      ? 'Datele nu pot fi actualizate momentan'
                      : 'Unable to update data right now'
                : isLoading
                ? context.l10n.loadingEllipsis
                : context.l10n.noStationAvailable);
        final waterLevel = hasReading && waterValue != null
            ? '${waterValue.toStringAsFixed(0)} $waterUnit'
            : context.l10n.noData;
        final status = hasReading
            ? (hasKnownTrend
                  ? _statusFor(context, trend)
                  : context.l10n.unknown)
            : context.l10n.noData;
        final lastUpdate = measurementTimestamp == null
            ? (snapshot.hasError
                  ? Localizations.localeOf(context).languageCode == 'ro'
                        ? 'Încercați din nou în câteva momente'
                        : 'Please try again in a few moments'
                  : context.l10n.waitingForData)
            : _freshnessLabel(
                context,
                measurementTimestamp,
                dataAge: waterResult?.dataAge,
                isStale: waterResult?.isStale ?? false,
              );
        final sourceLabel = hasReading
            ? _compactSourceName(
                    waterResult?.source ?? latestReading?.source,
                  ) ??
                  latestReading?.sourceName ??
                  station!.waterLevelSource
            : context.l10n.noSource;

        return PremiumLoadingShimmer(
          isLoading: isInitialLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = HomePremiumLayout.of(context);
              final narrow = constraints.maxWidth < 340;
              final hasFiniteHeight = constraints.maxHeight.isFinite;
              final compactHeightLimit =
                  layout.waterCardHeight *
                  (layout.isLandscapePhone ? 1.0 : .85);
              final compact =
                  hasFiniteHeight &&
                  constraints.maxHeight <= compactHeightLimit;
              final cardPadding = layout.isSmallPhone
                  ? 8.0
                  : (layout.isTablet ? 12.0 : 10.0);
              final trendColor = hasKnownTrend
                  ? _colorFor(trend)
                  : Colors.white54;
              final history = waterResult?.history ?? const <WaterLevel>[];
              final historyLoading =
                  station != null &&
                  _waterResultStationId == station.id &&
                  _isWaterResultLoading;
              final hasEnoughHistory = history.length >= 2;
              final canShowHistory =
                  reliabilityStatus == WaterUiStatus.availableHistory &&
                  hasEnoughHistory;
              final historyDelta = canShowHistory
                  ? _historyDeltaLabel(history, waterUnit)
                  : null;
              final isRo = Localizations.localeOf(context).languageCode == 'ro';

              if (isInitialLoading) {
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: cardPadding,
                    vertical: compact ? 6 : cardPadding,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17293A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.water_drop_rounded,
                            color: const Color(0xFF42A5F5),
                            size: 20 * layout.iconScale,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.l10n.waterLevel.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize:
                                    (compact ? 14 : 16) * layout.titleFontScale,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            isRo
                                ? 'Se \u00eencarc\u0103 datele\u2026'
                                : 'Loading data\u2026',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white70,
                              fontSize: compact ? 10 : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: cardPadding,
                  vertical: compact ? 6 : cardPadding,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF17293A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.water_drop_rounded,
                          color: const Color(0xFF42A5F5),
                          size: 20 * layout.iconScale,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Text(
                            context.l10n.waterLevel.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize:
                                  (compact ? 14 : 16) * layout.titleFontScale,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                sourceLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: narrow || compact ? 8 : 10,
                                ),
                              ),
                              Text(
                                lastUpdate,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: AppTextStyles.caption.copyWith(
                                  color: Colors.white54,
                                  fontSize: narrow || compact ? 7 : 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 1 : 3),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: narrow ? 3 : 4,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stationName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize: compact ? 10 : null,
                                  ),
                                ),
                                SizedBox(height: compact ? 1 : 3),
                                Text(
                                  waterLevel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize:
                                        (narrow ? 22 : 28) *
                                        layout.titleFontScale,
                                    height: 1,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: compact ? 2 : 4),
                                Row(
                                  children: [
                                    Icon(
                                      hasKnownTrend
                                          ? _iconFor(trend)
                                          : Icons.help_outline_rounded,
                                      color: trendColor,
                                      size: compact ? 14 : 16,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        status,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: trendColor,
                                          fontSize: narrow || compact ? 11 : 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: narrow ? 6 : 12),
                          Expanded(
                            flex: narrow ? 2 : 3,
                            child: Column(
                              children: [
                                Expanded(
                                  child: historyLoading
                                      ? const Center(
                                          child: SizedBox.square(
                                            dimension: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.8,
                                            ),
                                          ),
                                        )
                                      : canShowHistory
                                      ? CustomPaint(
                                          painter: _WaterSparklinePainter(
                                            readings: history,
                                            color: trendColor,
                                          ),
                                          child: const SizedBox.expand(),
                                        )
                                      : Center(
                                          child: Text(
                                            _historyStatusLabel(
                                              reliabilityStatus,
                                              isRo: isRo,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                  color: Colors.white54,
                                                  fontSize: narrow || compact
                                                      ? 8
                                                      : 10,
                                                ),
                                          ),
                                        ),
                                ),
                                SizedBox(height: compact ? 1 : 2),
                                if (historyDelta != null)
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: compact ? 1 : 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: trendColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: trendColor.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      historyDelta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.caption.copyWith(
                                        color: trendColor,
                                        fontSize: narrow || compact ? 8 : 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static Color _colorFor(WaterTrend trend) => switch (trend) {
    WaterTrend.rising => const Color(0xFF2196F3),
    WaterTrend.stable => const Color(0xFF43A047),
    WaterTrend.falling => const Color(0xFFE53935),
  };

  static IconData _iconFor(WaterTrend trend) => switch (trend) {
    WaterTrend.rising => Icons.arrow_upward_rounded,
    WaterTrend.stable => Icons.remove_rounded,
    WaterTrend.falling => Icons.arrow_downward_rounded,
  };

  static String _statusFor(BuildContext context, WaterTrend trend) =>
      switch (trend) {
        WaterTrend.rising => context.l10n.rising,
        WaterTrend.stable => context.l10n.stable,
        WaterTrend.falling => context.l10n.falling,
      };

  static String _historyDeltaLabel(List<WaterLevel> history, String unit) {
    final first = history.first;
    final last = history.last;
    final difference = (last.value - first.value).round();
    final sign = difference > 0 ? '+' : '';
    final elapsedHours = last.timestamp.difference(first.timestamp).inHours;
    final periodLabel = elapsedHours > 0
        ? ' / ${elapsedHours >= 24 ? 24 : elapsedHours} h'
        : '';

    return '$sign$difference $unit$periodLabel';
  }

  static String? _compactSourceName(WaterLevelSource? source) =>
      switch (source) {
        WaterLevelSource.afdj => 'AFDJ',
        WaterLevelSource.danubeHis => 'DanubeHIS',
        WaterLevelSource.danubeFis => 'DanubeFIS',
        WaterLevelSource.inhga => 'INHGA',
        WaterLevelSource.manualFallback => 'Manual',
        null => null,
      };

  // TODO(l10n): Move beta reliability labels into ARB in the localization sprint.
  static String _freshnessLabel(
    BuildContext context,
    DateTime timestamp, {
    required Duration? dataAge,
    required bool isStale,
  }) {
    if (timestamp.millisecondsSinceEpoch == 0) {
      return context.l10n.updateTimeUnavailable;
    }

    final measuredAge =
        dataAge ?? DateTime.now().difference(timestamp.toLocal());
    final age = measuredAge.isNegative ? Duration.zero : measuredAge;
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    if (age.inMinutes < 1) {
      return isRo ? 'Acum' : 'Now';
    }

    final ageLabel = _compactAgeLabel(age, isRo: isRo);
    if (isStale) {
      return isRo ? 'Vechi \u2022 $ageLabel' : 'Stale \u2022 $ageLabel';
    }
    return isRo ? 'Acum $ageLabel' : '$ageLabel ago';
  }

  static String _compactAgeLabel(Duration age, {required bool isRo}) {
    if (age.inMinutes < 60) {
      final value = age.inMinutes;
      if (!isRo) return '$value ${value == 1 ? 'minute' : 'minutes'}';
      return '$value ${value == 1 ? 'minut' : 'minute'}';
    }
    if (age.inHours < 24) {
      final value = age.inHours;
      if (!isRo) return '$value ${value == 1 ? 'hour' : 'hours'}';
      return '$value ${value == 1 ? 'or\u0103' : 'ore'}';
    }
    final value = age.inDays;
    if (!isRo) return '$value ${value == 1 ? 'day' : 'days'}';
    return '$value ${value == 1 ? 'zi' : 'zile'}';
  }

  static String _historyStatusLabel(
    WaterUiStatus status, {
    required bool isRo,
  }) => switch (status) {
    WaterUiStatus.availableHistory =>
      isRo ? 'Istoric 24h disponibil' : '24h history available',
    WaterUiStatus.insufficientHistory =>
      isRo ? 'Istoric 24h insuficient' : 'Insufficient 24h history',
    WaterUiStatus.providerError =>
      isRo
          ? 'Istoric temporar indisponibil'
          : 'History temporarily unavailable',
    WaterUiStatus.unavailable =>
      isRo ? 'Date temporar indisponibile' : 'Data temporarily unavailable',
  };
}

class _WaterSparklinePainter extends CustomPainter {
  const _WaterSparklinePainter({required this.readings, required this.color});

  final List<WaterLevel> readings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.length < 2 || size.isEmpty) return;

    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final valueRange = maximum - minimum;
    final firstTimestamp = readings.first.timestamp.millisecondsSinceEpoch;
    final lastTimestamp = readings.last.timestamp.millisecondsSinceEpoch;
    final timeRange = lastTimestamp - firstTimestamp;
    const inset = 3.0;
    final chartWidth = (size.width - (inset * 2)).clamp(0.0, size.width);
    final chartHeight = (size.height - (inset * 2)).clamp(0.0, size.height);
    final path = Path();
    final points = <Offset>[];

    for (var index = 0; index < readings.length; index++) {
      final reading = readings[index];
      final xFactor = timeRange == 0
          ? index / (readings.length - 1)
          : (reading.timestamp.millisecondsSinceEpoch - firstTimestamp) /
                timeRange;
      final yFactor = valueRange == 0
          ? .5
          : (reading.value - minimum) / valueRange;
      final point = Offset(
        inset + (chartWidth * xFactor),
        inset + chartHeight - (chartHeight * yFactor),
      );
      points.add(point);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height - inset)
      ..lineTo(points.first.dx, size.height - inset)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final lastPoint = points.last;
    canvas.drawCircle(
      lastPoint,
      5,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(lastPoint, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WaterSparklinePainter oldDelegate) {
    return oldDelegate.readings != readings || oldDelegate.color != color;
  }
}
