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
  bool _isFavorite = false;
  bool _favoriteLoading = true;
  WaterStationDetailsRange _selectedRange = WaterStationDetailsRange.sevenDays;
  WaterStationDetailsResult? _detailsResult;
  bool _detailsLoading = true;
  bool _historyLoading = true;
  bool _detailsLoadFailed = false;
  int _detailsRequestId = 0;
  late final Future<WeatherData> _weather;

  Station get station => widget.station;

  @override
  void initState() {
    super.initState();
    _isFavorite = station.isFavorite;
    _weather = WeatherService().getCurrentWeather(fallbackStation: station);
    unawaited(_loadDetails());
    _loadFavorite();
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
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final freshness = details?.measurementTimestamp == null
        ? context.l10n.updateTimeUnavailable
        : WaterFreshnessFormatter.format(
            measurementTimestamp: details!.measurementTimestamp!,
            now: DateTime.now(),
            isStale: details.isStale,
            locale: Localizations.localeOf(context).languageCode,
          );
    return Scaffold(
      appBar: AppBar(title: Text(station.name), centerTitle: true),
      body: SingleChildScrollView(
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
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      station.river,
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _detailsLoading && details == null
                          ? context.l10n.loadingEllipsis
                          : '${isRo ? 'Surs\u0103' : 'Source'}: '
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
                          : '${isRo ? 'Actualizat' : 'Updated'}: $freshness',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    if (details?.isStale == true)
                      Text(
                        isRo ? 'Date vechi' : 'Stale data',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text(
              isRo
                  ? 'Informa\u021bii despre sta\u021bie'
                  : 'Station information',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                            isRo
                                ? 'Istoricul nivelului apei'
                                : 'Water level history',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<WaterStationDetailsRange>(
                      segments: [
                        ButtonSegment(
                          value: WaterStationDetailsRange.sevenDays,
                          label: Text(isRo ? '7 zile' : '7 days'),
                        ),
                        ButtonSegment(
                          value: WaterStationDetailsRange.thirtyDays,
                          label: Text(isRo ? '30 zile' : '30 days'),
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
                                  WaterStationDetailsHistoryStatus.providerError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (details.dailyDeltaCm case final delta?) ...[
                        const SizedBox(height: 6),
                        Text(_deltaLabel(delta, current?.unit ?? 'cm', isRo)),
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
                                    Text(_historyDateLabel(reading)),
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
                subtitle: Text(_waterInsight(station)),
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
                      ? 'Weather unavailable'
                      : weather == null
                      ? 'Loading weather...'
                      : '${weather.temperature.round()}° • '
                            '${weather.condition} • '
                            '${weather.windSpeed.toStringAsFixed(1)} km/h wind';
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
                  _isFavorite ? 'Remove from Favourites' : 'Add to Favourites',
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
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
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    return switch (status) {
      WaterStationDetailsHistoryStatus.available =>
        isRo ? 'Istoric disponibil' : 'History available',
      WaterStationDetailsHistoryStatus.insufficientHistory =>
        isRo ? 'Istoric insuficient' : 'Insufficient history',
      WaterStationDetailsHistoryStatus.providerError =>
        isRo ? 'Date temporar indisponibile' : 'Data temporarily unavailable',
      WaterStationDetailsHistoryStatus.unavailable ||
      null => isRo ? 'Istoric insuficient' : 'Insufficient history',
    };
  }

  static String _historyDateLabel(WaterLevel reading) {
    final local = reading.timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}.${local.month}.${local.year}  $hour:$minute';
  }

  static String _deltaLabel(double delta, String unit, bool isRo) {
    final sign = delta > 0 ? '+' : '';
    final value = '$sign${delta.toStringAsFixed(0)} $unit';
    return isRo
        ? '$value fa\u021b\u0103 de citirea anterioar\u0103'
        : '$value since previous reading';
  }

  static String _waterInsight(Station station) {
    if (!station.hasWaterLevel) {
      return 'Not enough verified water data for an insight.';
    }
    if (!station.hasKnownTrend) {
      return 'Not enough history for a water insight.';
    }
    return switch (station.trend) {
      WaterTrend.rising =>
        'The level is rising. Expect stronger current near banks.',
      WaterTrend.falling =>
        'The level is falling. Fish may move to deeper or slower water.',
      WaterTrend.stable =>
        'The level is stable, with more predictable water conditions.',
    };
  }
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
