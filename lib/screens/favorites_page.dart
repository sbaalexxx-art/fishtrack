import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/station.dart';
import '../services/favorite_stations_service.dart';
import '../services/water_service.dart';
import '../widgets/loading_list_skeleton.dart';
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
      appBar: AppBar(title: Text(context.l10n.favouriteStations)),
      body: SafeArea(
        child: FutureBuilder<List<Station>>(
          future: _favorites,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingListSkeleton();
            }
            if (snapshot.hasError) {
              return _FavoriteMessage(
                message: !_service.isAuthenticated
                    ? context.l10n.signInForFavorites
                    : context.l10n.favoritesUnavailable,
                onRetry: _refresh,
              );
            }
            final stations = snapshot.data ?? const [];
            if (stations.isEmpty) {
              return _FavoriteMessage(
                message: context.l10n.noFavouriteStations,
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
                      title: Text(
                        station.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_stationSubtitle(context, station)),
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

  static String _stationSubtitle(BuildContext context, Station station) {
    if (!station.hasWaterLevel) {
      return station.river.isEmpty
          ? context.l10n.waterLevelUnavailable
          : '${station.river} • ${context.l10n.waterLevelUnavailable}';
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
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRetry,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite_border_rounded, size: 48),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(message, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: Text(context.l10n.refresh)),
            ],
          ),
        ),
      ],
    ),
  );
}
