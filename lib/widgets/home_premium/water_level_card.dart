import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/formatters/water_freshness_formatter.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../models/water_level.dart';
import '../../services/water_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

class WaterLevelCardPremium extends StatefulWidget {
  const WaterLevelCardPremium({
    super.key,
    required this.layout,
    this.selectedStation,
  });

  final HomePremiumLayout layout;
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
            : WaterFreshnessFormatter.format(
                measurementTimestamp: measurementTimestamp,
                now: DateTime.now(),
                isStale: waterResult?.isStale ?? false,
                locale: Localizations.localeOf(context).languageCode,
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
              final layout = widget.layout;
              final narrow = constraints.maxWidth < 340;
              final hasFiniteHeight = constraints.maxHeight.isFinite;
              final compactHeightLimit = layout.isTablet ? 145.0 : 130.0;
              final compact =
                  hasFiniteHeight &&
                  constraints.maxHeight <= compactHeightLimit;
              final cardPadding = layout.isSmallPhone
                  ? 7.0
                  : (layout.isTablet ? 10.0 : 8.0);
              final verticalPadding = (compact ? 6.0 : cardPadding) * .80;
              final isStale = waterResult?.isStale ?? false;
              final trendColor = hasKnownTrend && !isStale
                  ? _colorFor(trend)
                  : const Color(0xFF9AA7B2);
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
              final trendStatus = isStale
                  ? (isRo ? 'Date neactualizate' : 'Stale data')
                  : status;
              final badgeLabel = hasReading
                  ? (isRo ? 'DATE REALE' : 'LIVE DATA')
                  : (isRo ? 'FĂRĂ DATE' : 'NO DATA');
              final badgeColor = hasReading
                  ? const Color(0xFF00BCD4)
                  : Colors.white38;
              final historyTitle = canShowHistory
                  ? (isRo ? 'ISTORIC REAL' : 'REAL HISTORY')
                  : (isRo ? 'ISTORIC' : 'HISTORY');

              if (isInitialLoading) {
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: cardPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF162F40), Color(0xFF0D2230)],
                    ),
                    borderRadius: BorderRadius.circular(15),
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
                  vertical: verticalPadding,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF162F40), Color(0xFF0D2230)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: const Color(0xFF00BCD4).withValues(alpha: 0.38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00BCD4).withValues(alpha: 0.06),
                      blurRadius: 16,
                      spreadRadius: -9,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: compact ? 26 : 30,
                          height: compact ? 26 : 30,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF00BCD4,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFF00BCD4,
                              ).withValues(alpha: 0.46),
                            ),
                          ),
                          child: Icon(
                            Icons.water_rounded,
                            color: const Color(0xFF00BCD4),
                            size: (compact ? 15 : 17) * layout.iconScale,
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.waterLevel.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.cardTitle.copyWith(
                                  fontSize:
                                      (compact ? 13 : 15) *
                                      layout.titleFontScale,
                                ),
                              ),
                              Text(
                                stationName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption.copyWith(
                                  color: Colors.white70,
                                  fontSize: narrow || compact ? 8 : 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 6.5 : 7.5,
                            vertical: compact ? 1.5 : 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.46),
                            ),
                          ),
                          child: Text(
                            badgeLabel,
                            maxLines: 1,
                            style: AppTextStyles.caption.copyWith(
                              color: badgeColor,
                              fontSize: narrow || compact ? 7.5 : 8.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.48,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 2 : 4),
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
                                  waterLevel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize:
                                        (narrow ? 22 : 29) *
                                        layout.titleFontScale,
                                    height: 1,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: compact ? 1.5 : 3),
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
                                        trendStatus,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: trendColor,
                                          fontSize: narrow || compact ? 10 : 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: narrow ? 6 : 10),
                          Expanded(
                            flex: narrow ? 2 : 3,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 4 : 6,
                                vertical: compact ? 2 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF061720,
                                ).withValues(alpha: 0.52),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      (canShowHistory
                                              ? trendColor
                                              : const Color(0xFF00BCD4))
                                          .withValues(alpha: 0.20),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    historyTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption.copyWith(
                                      color: Colors.white60,
                                      fontSize: narrow || compact ? 7 : 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.55,
                                    ),
                                  ),
                                  SizedBox(height: compact ? 1.5 : 2.5),
                                  Container(
                                    height: 1,
                                    color:
                                        (canShowHistory
                                                ? trendColor
                                                : const Color(0xFF00BCD4))
                                            .withValues(alpha: 0.14),
                                  ),
                                  SizedBox(height: compact ? 1.5 : 2.5),
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
                                                        ? 7
                                                        : 9,
                                                  ),
                                            ),
                                          ),
                                  ),
                                  if (historyDelta != null) ...[
                                    SizedBox(height: compact ? 1 : 2),
                                    Text(
                                      historyDelta,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.caption.copyWith(
                                        color: trendColor,
                                        fontSize: narrow || compact ? 7 : 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${isRo ? 'Sursă' : 'Source'}: $sourceLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white60,
                              fontSize: narrow || compact ? 7 : 8.5,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 6 : 10),
                        Flexible(
                          child: Text(
                            '${isRo ? 'Actualizat' : 'Updated'}: $lastUpdate',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white60,
                              fontSize: narrow || compact ? 7 : 8.5,
                            ),
                          ),
                        ),
                      ],
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
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.3
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
