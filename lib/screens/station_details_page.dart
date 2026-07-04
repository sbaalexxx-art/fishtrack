import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';
import '../models/weather.dart';
import '../services/water_service.dart';
import '../services/weather_service.dart';
import '../widgets/recent_catches.dart';
import 'add_catch_page.dart';
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
  late final Future<List<WaterLevelReading>> _history;
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

  Future<List<WaterLevelReading>> _loadHistory() async {
    final response = await Supabase.instance.client
        .from('water_levels')
        .select('value, timestamp, trend')
        .eq('station_id', station.id)
        .order('timestamp', ascending: false)
        .limit(30)
        .timeout(const Duration(seconds: 12));
    return response
        .map(WaterLevelReading.tryFromJson)
        .whereType<WaterLevelReading>()
        .toList(growable: false);
  }

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

  Future<void> _reportCatch() async {
    WaterService().selectStation(station);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<bool>(builder: (_) => const AddCatchPage()));
  }

  Color get trendColor {
    switch (station.trend) {
      case WaterTrend.rising:
        return Colors.green;

      case WaterTrend.falling:
        return Colors.red;

      case WaterTrend.stable:
        return Colors.orange;
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

                    const SizedBox(height: 24),

                    Text(
                      "${station.level.toStringAsFixed(0)} cm",
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
                    ),

                    const SizedBox(height: 12),

                    Text(
                      "Actualizat: ${station.lastUpdate.day}.${station.lastUpdate.month}.${station.lastUpdate.year}",
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
              child: FutureBuilder<List<WaterLevelReading>>(
                future: _history,
                builder: (context, snapshot) {
                  final readings = snapshot.data ?? const [];
                  final subtitle = snapshot.hasError
                      ? 'Water history unavailable'
                      : snapshot.connectionState == ConnectionState.waiting
                      ? 'Loading water history...'
                      : readings.isEmpty
                      ? 'No historical measurements'
                      : readings
                            .take(4)
                            .map(
                              (reading) =>
                                  '${reading.value.toStringAsFixed(0)} cm',
                            )
                            .join(' • ');
                  return ListTile(
                    leading: const Icon(Icons.show_chart, color: Colors.blue),
                    title: const Text('Water level history'),
                    subtitle: Text(subtitle),
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

            const Text(
              "Capturi recente",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            RecentCatches(stationId: station.id),

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

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _reportCatch,
                icon: const Icon(Icons.campaign),
                label: const Text('Report a Catch'),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class WaterLevelReading {
  const WaterLevelReading({required this.value, required this.timestamp});

  final double value;
  final DateTime timestamp;

  static WaterLevelReading? tryFromJson(Map<String, dynamic> json) {
    final value = json['value'] is num
        ? (json['value'] as num).toDouble()
        : double.tryParse(json['value']?.toString() ?? '');
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    if (value == null || timestamp == null) return null;
    return WaterLevelReading(value: value, timestamp: timestamp.toLocal());
  }
}
