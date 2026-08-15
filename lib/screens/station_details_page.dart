import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters/water_freshness_formatter.dart';
import '../l10n/l10n.dart';

import '../models/station.dart';
import '../models/water_level.dart';
import '../models/weather.dart';
import '../services/favorite_stations_service.dart';
import '../services/water_service.dart';
import '../services/weather_service.dart';

class StationDetailsPage extends StatefulWidget {
  final Station station;

  const StationDetailsPage({super.key, required this.station});

  @override
  State<StationDetailsPage> createState() => _StationDetailsPageState();
}

class _StationDetailsPageState extends State<StationDetailsPage> {
  final _favoritesService = const FavoriteStationsService();
  final _waterService = WaterService();
  final _weatherService = WeatherService();
  bool _isFavorite = false;
  bool _favoriteLoading = true;
  WaterStationDetailsRange _selectedRange = WaterStationDetailsRange.sevenDays;
  WaterStationDetailsResult? _detailsResult;
  bool _detailsLoading = true;
  bool _historyLoading = true;
  bool _detailsLoadFailed = false;
  int _detailsRequestId = 0;
  late Future<WeatherData> _weather;

  Station get station => widget.station;

  @override
  void initState() {
    super.initState();
    _isFavorite = station.isFavorite;
    _loadWeather();
    unawaited(_loadDetails());
    _loadFavorite();
  }

  @override
  void didUpdateWidget(covariant StationDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != station.id ||
        oldWidget.station.latitude != station.latitude ||
        oldWidget.station.longitude != station.longitude) {
      _loadWeather();
    }
  }

  void _loadWeather() {
    _weather = _weatherService.getWeatherForStation(station);
  }

  Future<void> _loadDetails() async {
    final requestId = ++_detailsRequestId;
    final requestedRange = _selectedRange;
    try {
      final result = await _waterService.getStationDetailsResult(
        station,
        range: requestedRange,
      );
      if (!mounted || requestId != _detailsRequestId) return;
      setState(() {
        _detailsResult = result;
        _detailsLoading = false;
        _historyLoading = false;
        _detailsLoadFailed = false;
      });
    } on Exception {
      if (!mounted || requestId != _detailsRequestId) return;
      setState(() {
        _detailsLoading = false;
        _historyLoading = false;
        _detailsLoadFailed = true;
      });
    }
  }

  void _selectRange(WaterStationDetailsRange range) {
    if (range == _selectedRange) return;
    setState(() {
      _selectedRange = range;
      _historyLoading = true;
      _detailsLoadFailed = false;
    });
    unawaited(_loadDetails());
  }

  Future<void> _loadFavorite() async {
    try {
      final isFavorite = await _favoritesService.isFavorite(station.id);
      if (mounted) setState(() => _isFavorite = isFavorite);
    } on FavoriteException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favoriteLoading = true);
    try {
      final isFavorite = await _favoritesService.setFavorite(
        station.id,
        favorite: !_isFavorite,
      );
      if (mounted) setState(() => _isFavorite = isFavorite);
    } on FavoriteException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static Color _trendColor(WaterTrend? trend) {
    switch (trend) {
      case WaterTrend.rising:
        return Colors.blue;

      case WaterTrend.falling:
        return Colors.red;

      case WaterTrend.stable:
        return Colors.green;

      case null:
        return Colors.grey;
    }
  }

  static IconData _trendIcon(WaterTrend? trend) {
    switch (trend) {
      case WaterTrend.rising:
        return Icons.trending_up;

      case WaterTrend.falling:
        return Icons.trending_down;

      case WaterTrend.stable:
        return Icons.trending_flat;

      case null:
        return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _detailsResult;
    final current = details?.currentReading;
    final hasCurrent = current != null;
    final history = _detailsLoadFailed
        ? const <WaterLevel>[]
        : details?.history ?? const <WaterLevel>[];
    final historyLoading = _historyLoading || details == null;
    final trend = details?.trend;
    final trendColor = _trendColor(trend);
    final freshnessTimestamp = details?.effectiveFreshnessTimestamp;
    final freshness = freshnessTimestamp == null
        ? context.l10n.updateTimeUnavailable
        : WaterFreshnessFormatter.format(
            freshnessTimestamp: freshnessTimestamp,
            now: DateTime.now(),
            isStale: details!.isStale,
            locale: Localizations.localeOf(context).languageCode,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 38,
                        backgroundColor: Colors.blue,
                        child: Icon(
                          Icons.water_drop,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        station.river,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _detailsLoading && details == null
                            ? context.l10n.loadingEllipsis
                            : '${context.l10n.source}: '
                                  '${hasCurrent ? _sourceLabel(details!.source) : context.l10n.noSource}',
                        style: const TextStyle(color: Colors.grey),
                      ),

                      const SizedBox(height: 24),

                      Text(
                        _detailsLoading && details == null
                            ? context.l10n.loadingEllipsis
                            : hasCurrent
                            ? '${current.value.toStringAsFixed(0)} ${current.unit}'
                            : context.l10n.noData,
                        style: const TextStyle(
                          fontSize: 46,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_trendIcon(trend), color: trendColor),
                          const SizedBox(width: 8),
                          Text(
                            _detailsLoading && details == null
                                ? context.l10n.loadingEllipsis
                                : _trendLabel(context, trend),
                            style: TextStyle(
                              color: trendColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        _detailsLoading && details == null
                            ? context.l10n.loadingEllipsis
                            : '${context.l10n.lastUpdated}: $freshness',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                context.l10n.stationDetails,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.red),
                  title: Text(context.l10n.coordinates),
                  subtitle: Text("${station.latitude}, ${station.longitude}"),
                ),
              ),

              const SizedBox(height: 12),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.show_chart, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.l10n.waterLevelHistory,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<WaterStationDetailsRange>(
                        segments: [
                          ButtonSegment(
                            value: WaterStationDetailsRange.sevenDays,
                            label: const Text('7D'),
                          ),
                          ButtonSegment(
                            value: WaterStationDetailsRange.thirtyDays,
                            label: const Text('30D'),
                          ),
                        ],
                        selected: {_selectedRange},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            _selectRange(selection.first);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      if (historyLoading)
                        const SizedBox(
                          height: 150,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        Text(
                          _historyStatusLabel(
                            context,
                            _detailsLoadFailed
                                ? WaterStationDetailsHistoryStatus.providerError
                                : details.historyStatus,
                          ),
                          style: TextStyle(
                            color:
                                details.historyStatus ==
                                    WaterStationDetailsHistoryStatus
                                        .providerError
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (details.dailyDeltaCm case final delta?) ...[
                          const SizedBox(height: 6),
                          Text(
                            _deltaLabel(context, delta, current?.unit ?? 'cm'),
                          ),
                        ],
                        if (history.length >= 2) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 150,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _WaterHistoryPainter(history),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...history.reversed
                              .take(30)
                              .map(
                                (reading) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _historyDateLabel(reading),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${reading.value.toStringAsFixed(0)} '
                                        '${reading.unit}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome, color: Colors.teal),
                  title: Text(context.l10n.aiWaterInsight),
                  subtitle: Text(_waterInsight(context, station)),
                ),
              ),

              const SizedBox(height: 12),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: FutureBuilder<WeatherData>(
                  future: _weather,
                  builder: (context, snapshot) {
                    final weather = snapshot.data;
                    final subtitle = snapshot.hasError
                        ? context.l10n.updateFailed
                        : weather == null
                        ? context.l10n.loadingEllipsis
                        : '${weather.temperature.round()}° • '
                              '${_weatherCondition(context, weather.condition)} • '
                              '${context.l10n.wind}: '
                              '${weather.windSpeed.toStringAsFixed(1)} km/h';
                    return ListTile(
                      leading: const Icon(Icons.cloud, color: Colors.orange),
                      title: Text(context.l10n.weather),
                      subtitle: Text(subtitle),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _favoriteLoading ? null : _toggleFavorite,
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  label: Text(
                    _isFavorite
                        ? context.l10n.removeFromFavourites
                        : context.l10n.addToFavourites,
                  ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  static String _sourceLabel(WaterLevelSource? source) => switch (source) {
    WaterLevelSource.afdj => 'AFDJ',
    WaterLevelSource.danubeHis => 'DanubeHIS',
    WaterLevelSource.danubeFis => 'DanubeFIS',
    WaterLevelSource.inhga => 'INHGA',
    WaterLevelSource.manualFallback => 'Manual',
    null => '—',
  };

  static String _trendLabel(BuildContext context, WaterTrend? trend) =>
      switch (trend) {
        WaterTrend.rising => context.l10n.rising,
        WaterTrend.falling => context.l10n.falling,
        WaterTrend.stable => context.l10n.stable,
        null => context.l10n.unknown,
      };

  static String _historyStatusLabel(
    BuildContext context,
    WaterStationDetailsHistoryStatus? status,
  ) {
    return switch (status) {
      WaterStationDetailsHistoryStatus.available =>
        context.l10n.waterHistoryObservations,
      WaterStationDetailsHistoryStatus.insufficientHistory =>
        context.l10n.notEnoughHistory,
      WaterStationDetailsHistoryStatus.providerError =>
        context.l10n.updateFailed,
      WaterStationDetailsHistoryStatus.unavailable ||
      null => context.l10n.notEnoughHistory,
    };
  }

  static String _historyDateLabel(WaterLevel reading) {
    final local = reading.timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}.${local.month}.${local.year}  $hour:$minute';
  }

  static String _deltaLabel(BuildContext context, double delta, String unit) {
    final sign = delta > 0 ? '+' : '';
    final value = '$sign${delta.toStringAsFixed(0)} $unit';
    return '$value · ${context.l10n.waterComparedWithLastReading}';
  }

  static String _waterInsight(BuildContext context, Station station) {
    if (!station.hasWaterLevel) {
      return context.l10n.dataUnavailable;
    }
    if (!station.hasKnownTrend) {
      return context.l10n.waterNotEnoughHistoryInsight;
    }
    return _trendLabel(context, station.trend);
  }

  static String _weatherCondition(BuildContext context, String condition) =>
      condition == 'Clear sky' ? context.l10n.clearSky : condition;
}

class _WaterHistoryPainter extends CustomPainter {
  const _WaterHistoryPainter(this.readings);

  final List<WaterLevel> readings;

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.length < 2) return;
    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final range = maximum - minimum;
    final chartHeight = size.height - 28;
    final path = Path();
    final points = <Offset>[];
    for (var index = 0; index < readings.length; index++) {
      final x = size.width * index / (readings.length - 1);
      final normalized = range == 0
          ? .5
          : (readings[index].value - minimum) / range;
      final y = 14 + chartHeight - (normalized * chartHeight);
      points.add(Offset(x, y));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final pointPaint = Paint()..color = Colors.blue;
    for (final point in points) {
      canvas.drawCircle(point, 3.5, pointPaint);
    }

    final minIndex = readings.indexWhere((reading) => reading.value == minimum);
    final maxIndex = readings.indexWhere((reading) => reading.value == maximum);
    final labelIndexes = <int>{minIndex, maxIndex, readings.length - 1};
    for (final index in labelIndexes) {
      final reading = readings[index];
      final label = TextPainter(
        text: TextSpan(
          text: '${reading.value.toStringAsFixed(0)} ${reading.unit}',
          style: const TextStyle(
            color: Colors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final point = points[index];
      final x = (point.dx - label.width / 2).clamp(
        0.0,
        size.width - label.width,
      );
      final y = point.dy < 24 ? point.dy + 6 : point.dy - label.height - 6;
      label.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(_WaterHistoryPainter oldDelegate) =>
      oldDelegate.readings != readings;
}
