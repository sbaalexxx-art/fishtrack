import 'package:flutter/material.dart';

import '../models/station.dart';
import '../models/water_level.dart';
import '../models/weather.dart';
import '../services/water_service.dart';
import '../services/weather_service.dart';
import 'favorites_page.dart';

class StationDetailsPage extends StatefulWidget {
  final Station station;

  const StationDetailsPage({super.key, required this.station});

  @override
  State<StationDetailsPage> createState() => _StationDetailsPageState();
}

class _StationDetailsPageState extends State<StationDetailsPage> {
  final _favoritesRepository = const FavoriteStationsRepository();
  bool _isFavorite = false;
  bool _favoriteLoading = true;
  late final Future<List<WaterLevel>> _history;
  late final Future<WeatherData> _weather;

  Station get station => widget.station;

  @override
  void initState() {
    super.initState();
    _isFavorite = station.isFavorite;
    _history = _loadHistory();
    _weather = WeatherService().getCurrentWeather(fallbackStation: station);
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    try {
      final isFavorite = await _favoritesRepository.isFavorite(station.id);
      if (mounted) setState(() => _isFavorite = isFavorite);
    } on FavoriteException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _favoriteLoading = false);
    }
  }

  Future<List<WaterLevel>> _loadHistory() =>
      WaterService().getHistory(station.id, stationName: station.name);

  Future<void> _toggleFavorite() async {
    setState(() => _favoriteLoading = true);
    try {
      final isFavorite = await _favoritesRepository.toggle(
        station.id,
        isFavorite: _isFavorite,
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

  Color get trendColor {
    switch (station.trend) {
      case WaterTrend.rising:
        return Colors.blue;

      case WaterTrend.falling:
        return Colors.red;

      case WaterTrend.stable:
        return Colors.green;
    }
  }

  IconData get trendIcon {
    switch (station.trend) {
      case WaterTrend.rising:
        return Icons.trending_up;

      case WaterTrend.falling:
        return Icons.trending_down;

      case WaterTrend.stable:
        return Icons.trending_flat;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      station.hasWaterLevel
                          ? 'Source: ${station.waterLevelSource}'
                          : 'Source: No data',
                      style: const TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      station.hasWaterLevel
                          ? '${station.level.toStringAsFixed(0)} '
                                '${station.waterLevelUnit}'
                          : 'No data',
                      style: const TextStyle(
                        fontSize: 46,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    FutureBuilder<List<WaterLevel>>(
                      future: _history,
                      builder: (context, snapshot) {
                        final readings = snapshot.data ?? const [];
                        if (!station.hasWaterLevel || readings.length < 2) {
                          return const Text(
                            'Not enough history for trend',
                            style: TextStyle(color: Colors.grey),
                          );
                        }
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(trendIcon, color: trendColor),
                            const SizedBox(width: 8),
                            Text(
                              station.trendText,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _updatedLabel(station.lastUpdate),
                      style: const TextStyle(color: Colors.grey),
                    ),
                    Text(
                      _relativeUpdate(station.lastUpdate),
                      style: const TextStyle(color: Colors.grey),
                    ),
                    if (_freshnessWarning(station.lastUpdate)
                        case final warning?)
                      Text(
                        warning,
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

            const Text(
              "Informații despre stație",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const Icon(Icons.location_on, color: Colors.red),
                title: const Text("Coordonate"),
                subtitle: Text("${station.latitude}, ${station.longitude}"),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: FutureBuilder<List<WaterLevel>>(
                future: _history,
                builder: (context, snapshot) {
                  final readings = snapshot.data ?? const [];
                  final subtitle = snapshot.hasError
                      ? 'Water history unavailable'
                      : snapshot.connectionState == ConnectionState.waiting
                      ? 'Loading water history...'
                      : readings.isEmpty
                      ? 'Water history will appear here'
                      : readings.length < 2
                      ? 'Not enough history for trend'
                      : _deltaLabel(readings[0], readings[1]);
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.show_chart, color: Colors.blue),
                            SizedBox(width: 12),
                            Text('Water level history'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(subtitle),
                        if (readings.isEmpty &&
                            snapshot.connectionState !=
                                ConnectionState.waiting) ...[
                          const SizedBox(height: 12),
                          Container(
                            height: 150,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.show_chart, color: Colors.grey),
                                SizedBox(height: 6),
                                Text(
                                  'Water history will appear here',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ] else if (readings.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 150,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _WaterHistoryPainter(
                                readings.reversed.toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...readings
                              .take(14)
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
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ListTile(
                leading: const Icon(Icons.auto_awesome, color: Colors.teal),
                title: const Text('AI water insight'),
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
                    title: const Text('Weather'),
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
                  _isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  static String _updatedLabel(DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch == 0) {
      return 'Not available';
    }
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Updated: ${local.day}.${local.month}.${local.year} $hour:$minute';
  }

  static String _relativeUpdate(DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch == 0) return 'Update age unknown';
    final difference = DateTime.now().difference(timestamp.toLocal());
    if (difference.isNegative || difference.inMinutes < 60) {
      return 'Updated less than 1 hour ago';
    }
    if (difference.inHours < 24) {
      return 'Updated ${difference.inHours} hours ago';
    }
    return 'Updated ${difference.inDays} days ago';
  }

  static String? _freshnessWarning(DateTime timestamp) {
    if (timestamp.millisecondsSinceEpoch == 0) return null;
    final age = DateTime.now().difference(timestamp.toLocal());
    if (age.inHours > 24) return 'Data is outdated';
    if (age.inHours > 12) return 'Data may be delayed';
    return null;
  }

  static String _historyDateLabel(WaterLevel reading) {
    final local = reading.timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day}.${local.month}.${local.year}  $hour:$minute';
  }

  static String _deltaLabel(WaterLevel latest, WaterLevel previous) {
    final delta = latest.value - previous.value;
    final sign = delta > 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(0)} ${latest.unit} '
        'since previous reading';
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
