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
      WaterService().getHistory(station.id);

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

                    const Text(
                      'Official source pending',
                      style: TextStyle(color: Colors.grey),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      station.hasWaterLevel
                          ? "${station.level.toStringAsFixed(0)} cm"
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
                        final hasHistory =
                            snapshot.hasData && snapshot.data!.isNotEmpty;
                        if (!station.hasWaterLevel || !hasHistory) {
                          return const Text(
                            'Unknown',
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
                      : readings
                            .take(4)
                            .map(
                              (reading) =>
                                  '${reading.value.toStringAsFixed(0)} cm',
                            )
                            .join(' • ');
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
                            height: 120,
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
                            height: 120,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _WaterHistoryPainter(
                                readings.reversed.toList(),
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
    final path = Path();
    for (var index = 0; index < readings.length; index++) {
      final x = size.width * index / (readings.length - 1);
      final normalized = range == 0
          ? .5
          : (readings[index].value - minimum) / range;
      final y = size.height - (normalized * size.height);
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
  }

  @override
  bool shouldRepaint(_WaterHistoryPainter oldDelegate) =>
      oldDelegate.readings != readings;
}
