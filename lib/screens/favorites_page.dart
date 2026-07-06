import 'package:flutter/material.dart';

import '../models/station.dart';
import '../services/favorite_stations_service.dart';
import '../services/water_service.dart';
import 'station_details_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _service = const FavoriteStationsService();
  final _waterService = WaterService();
  late Future<List<Station>> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = _load();
    FavoriteStationsService.revision.addListener(_reload);
  }

  @override
  void dispose() {
    FavoriteStationsService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _favorites = _load());
  }

  Future<List<Station>> _load() async {
    if (!_service.isAuthenticated) {
      throw const FavoriteException(
        'Please sign in to view your favourite stations.',
      );
    }
    final results = await Future.wait([
      _waterService.getStations(),
      _service.getFavoriteIds(),
    ]);
    final stations = results[0] as List<Station>;
    final ids = results[1] as Set<String>;
    return stations.where((station) => ids.contains(station.id)).toList();
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _favorites = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourite Stations')),
      body: SafeArea(
        child: FutureBuilder<List<Station>>(
          future: _favorites,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _FavoriteMessage(
                message: snapshot.error is FavoriteException
                    ? (snapshot.error! as FavoriteException).message
                    : 'Favourite stations are unavailable.',
                onRetry: _refresh,
              );
            }
            final stations = snapshot.data ?? const [];
            if (stations.isEmpty) {
              return _FavoriteMessage(
                message: 'No favourite stations yet.',
                onRetry: _refresh,
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                itemCount: stations.length,
                itemBuilder: (context, index) {
                  final station = stations[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.water_drop_outlined),
                      title: Text(station.name),
                      subtitle: Text(_stationSubtitle(station)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StationDetailsPage(station: station),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  static String _stationSubtitle(Station station) {
    if (!station.hasWaterLevel) {
      return station.river.isEmpty
          ? 'Water level unavailable'
          : '${station.river} • Water level unavailable';
    }
    final level =
        '${station.level.toStringAsFixed(0)} ${station.waterLevelUnit}';
    return station.river.isEmpty ? level : '${station.river} • $level';
  }
}

class _FavoriteMessage extends StatelessWidget {
  const _FavoriteMessage({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.favorite_border_rounded, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: onRetry, child: const Text('Refresh')),
      ],
    ),
  );
}
