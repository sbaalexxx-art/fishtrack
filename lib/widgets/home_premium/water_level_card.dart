import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
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

  Future<Station?> _loadStation(Station? fallbackStation) {
    return _waterService.getNearestStation(fallbackStation: fallbackStation);
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
                ? 'Unable to update data right now'
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
                  ? 'Please try again in a few moments'
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
              final compact = constraints.maxWidth < 180;
              final trendColor =
                  station?.hasWaterLevel == true &&
                      station?.hasKnownTrend == true
                  ? _colorFor(trend)
                  : Colors.white54;

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
                          child: Text(
                            context.l10n.waterLevel.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 16 * layout.titleFontScale,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                waterLevel,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize:
                                      (compact ? 25 : 30) *
                                      layout.titleFontScale,
                                  height: 1,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(
                                    _iconFor(trend),
                                    color: trendColor,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      status,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: trendColor,
                                        fontSize: compact ? 12 : 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: compact ? 46 : 68,
                          height: 38,
                          child: Center(
                            child: Text(
                              sourceLabel,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: compact ? 8 : 9,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
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
