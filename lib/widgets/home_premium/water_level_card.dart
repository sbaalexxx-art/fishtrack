import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_text_styles.dart';
import '../../models/station.dart';
import '../../services/water_service.dart';
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
                ? 'Water unavailable'
                : isLoading
                ? 'Loading...'
                : 'No station available');
        final waterLevel = station == null
            ? '--'
            : '${station.level.toStringAsFixed(0)} cm';
        final trend = station?.trend ?? WaterTrend.stable;
        final status = station == null ? '--' : _statusFor(trend);
        final lastUpdate = station == null
            ? (snapshot.hasError ? 'Update failed' : 'Waiting for data')
            : _relativeUpdate(station.lastUpdate);

        return LayoutBuilder(
          builder: (context, constraints) {
            final layout = HomePremiumLayout.of(context);
            final compact = constraints.maxWidth < 180;
            final trendColor = _colorFor(trend);

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
                          'WATER LEVEL',
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
                                    (compact ? 25 : 30) * layout.titleFontScale,
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
                            'History\nunavailable',
                            textAlign: TextAlign.center,
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

  static String _statusFor(WaterTrend trend) => switch (trend) {
    WaterTrend.rising => 'Rising',
    WaterTrend.stable => 'Stable',
    WaterTrend.falling => 'Falling',
  };

  static String _relativeUpdate(DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch == 0) {
      return 'Update time unknown';
    }

    final difference = DateTime.now().difference(timestamp.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return 'Updated just now';
    }
    if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return 'Updated ${difference.inHours} h ago';
    }
    return 'Updated ${difference.inDays} d ago';
  }
}
