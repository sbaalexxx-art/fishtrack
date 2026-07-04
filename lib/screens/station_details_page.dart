import 'package:flutter/material.dart';

import '../models/station.dart';
import '../services/water_service.dart';
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

  Station get station => widget.station;

  @override
  void initState() {
    super.initState();
    _isFavorite = station.isFavorite;
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
              child: const ListTile(
                leading: Icon(Icons.show_chart, color: Colors.blue),
                title: Text("Grafic nivel apă"),
                subtitle: Text("Disponibil în versiunea următoare"),
              ),
            ),

            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: const ListTile(
                leading: Icon(Icons.cloud, color: Colors.orange),
                title: Text("Meteo"),
                subtitle: Text("Integrare OpenWeather în curând"),
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
