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
  List<WaterLevel> _history = const [];
  String? _historyStationId;
  bool _isHistoryLoading = false;
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
    _history = const [];
    _historyStationId = null;
    _isHistoryLoading = true;

    final station = await _waterService.getNearestStation(
      fallbackStation: fallbackStation,
    );
    if (requestId != _stationRequestId) return station;

    if (station == null) {
      if (mounted) setState(() => _isHistoryLoading = false);
      return null;
    }

    unawaited(_loadHistory(station, requestId));
    return station;
  }

  Future<void> _loadHistory(Station station, int requestId) async {
    if (mounted && requestId == _stationRequestId) {
      setState(() {
        _history = const [];
        _historyStationId = station.id;
        _isHistoryLoading = true;
      });
    }

    List<WaterLevel> readings;
    try {
      readings = await _waterService.getHistory(
        station.id,
        stationName: station.name,
        limit: 72,
      );
    } on Exception {
      readings = const [];
    }

    if (!mounted ||
        requestId != _stationRequestId ||
        _historyStationId != station.id) {
      return;
    }

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(hours: 24));
    final filtered = readings
        .where((reading) => reading.value.isFinite)
        .where((reading) => !reading.timestamp.isBefore(cutoff))
        .where((reading) => !reading.timestamp.isAfter(now))
        .toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    setState(() {
      _history = filtered;
      _isHistoryLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Station?>(
      future: _stationFuture,
      builder: (context, snapshot) {
        final station = snapshot.data;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final stationName =
            station?.name ??
            (snapshot.hasError
                ? Localizations.localeOf(context).languageCode == 'ro'
                      ? 'Datele nu pot fi actualizate momentan'
                      : 'Unable to update data right now'
                : isLoading
                ? context.l10n.loadingEllipsis
                : context.l10n.noStationAvailable);
        final waterLevel = station == null
            ? '--'
            : station.hasWaterLevel
            ? '${station.level.toStringAsFixed(0)} ${station.waterLevelUnit}'
            : context.l10n.noData;
        final trend = station?.trend ?? WaterTrend.stable;
        final status = station == null
            ? '--'
            : station.hasWaterLevel
            ? (station.hasKnownTrend
                  ? _statusFor(context, trend)
                  : context.l10n.unknown)
            : context.l10n.noData;
        final lastUpdate = station == null
            ? (snapshot.hasError
                  ? Localizations.localeOf(context).languageCode == 'ro'
                        ? 'Încercați din nou în câteva momente'
                        : 'Please try again in a few moments'
                  : context.l10n.waitingForData)
            : _relativeUpdate(context, station.lastUpdate);
        final sourceLabel = station?.hasWaterLevel == true
            ? station!.waterLevelSource
            : context.l10n.noSource;

        return PremiumLoadingShimmer(
          isLoading: isLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = HomePremiumLayout.of(context);
              final narrow = constraints.maxWidth < 340;
              final trendColor =
                  station?.hasWaterLevel == true &&
                      station?.hasKnownTrend == true
                  ? _colorFor(trend)
                  : Colors.white54;
              final history = station != null &&
                      _historyStationId == station.id
                  ? _history
                  : const <WaterLevel>[];
              final historyLoading = station != null &&
                  _historyStationId == station.id &&
                  _isHistoryLoading;
              final isRo =
                  Localizations.localeOf(context).languageCode == 'ro';
              final colorScheme = Theme.of(context).colorScheme;

              return Container(
                padding: EdgeInsets.all(
                  layout.isSmallPhone ? 8 : (layout.isTablet ? 12 : 10),
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
                              fontSize: 16 * layout.titleFontScale,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            sourceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: narrow ? 8 : 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
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
                                  style: AppTextStyles.caption,
                                ),
                                const SizedBox(height: 3),
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
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      _iconFor(trend),
                                      color: trendColor,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        status,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: trendColor,
                                          fontSize: narrow ? 11 : 13,
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
                                      : history.length >= 2
                                      ? CustomPaint(
                                          painter: _WaterSparklinePainter(
                                            readings: history,
                                            lineColor: trendColor,
                                            pointColor: colorScheme.primary,
                                          ),
                                          child: const SizedBox.expand(),
                                        )
                                      : Center(
                                          child: Text(
                                            isRo
                                                ? 'Istoric indisponibil'
                                                : 'History unavailable',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                  color: Colors.white54,
                                                  fontSize: narrow ? 8 : 10,
                                                ),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isRo ? 'Trend 24 h' : '24h trend',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.white54,
                                    fontSize: narrow ? 8 : 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 14,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$status • $lastUpdate',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: narrow ? 10 : 12,
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

  static String _relativeUpdate(BuildContext context, DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch == 0) {
      return context.l10n.updateTimeUnavailable;
    }

    final difference = DateTime.now().difference(timestamp.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return context.l10n.updatedNow;
    }
    if (difference.inMinutes < 60) {
      return context.l10n.updatedMinutesAgo(difference.inMinutes);
    }
    if (difference.inHours < 24) {
      return context.l10n.updatedHoursAgo(difference.inHours);
    }
    return context.l10n.updatedDaysAgo(difference.inDays);
  }
}

class _WaterSparklinePainter extends CustomPainter {
  const _WaterSparklinePainter({
    required this.readings,
    required this.lineColor,
    required this.pointColor,
  });

  final List<WaterLevel> readings;
  final Color lineColor;
  final Color pointColor;

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

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final pointPaint = Paint()..color = pointColor;
    for (final point in points) {
      canvas.drawCircle(point, 2, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaterSparklinePainter oldDelegate) {
    return oldDelegate.readings != readings ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.pointColor != pointColor;
  }
}
