import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';
import '../services/water_service.dart';
import 'station_details_page.dart';

class FavoriteStationsRepository {
  const FavoriteStationsRepository({SupabaseClient? client}) : _client = client;

  static final ValueNotifier<int> revision = ValueNotifier(0);
  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<Set<String>> getFavoriteIds() => _guard(() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return <String>{};
    final response = await _supabase
        .from('favorites')
        .select('station_id')
        .eq('user_id', user.id);
    return response
        .whereType<Map>()
        .map((row) => row['station_id']?.toString())
        .whereType<String>()
        .toSet();
  });

  Future<bool> isFavorite(String stationId) async =>
      (await getFavoriteIds()).contains(stationId);

  Future<bool> toggle(String stationId, {required bool isFavorite}) => _guard(
    () async {
      final user = _supabase.auth.currentUser;
      if (user == null) throw const FavoriteException('Your session expired.');
      if (isFavorite) {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('station_id', stationId);
      } else {
        await _supabase.from('favorites').upsert({
          'user_id': user.id,
          'station_id': stationId,
        });
      }
      revision.value++;
      return !isFavorite;
    },
  );

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation().timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const FavoriteException('No internet connection.');
    } on TimeoutException {
      throw const FavoriteException('The request timed out.');
    } on PostgrestException catch (error) {
      throw FavoriteException(error.message);
    }
  }
}

class FavoriteException implements Exception {
  const FavoriteException(this.message);
  final String message;
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final _repository = const FavoriteStationsRepository();
  final _waterService = WaterService();
  late Future<List<Station>> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = _load();
    FavoriteStationsRepository.revision.addListener(_reload);
  }

  @override
  void dispose() {
    FavoriteStationsRepository.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _favorites = _load());
  }

  Future<List<Station>> _load() async {
    final results = await Future.wait([
      _waterService.getStations(),
      _repository.getFavoriteIds(),
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
      appBar: AppBar(title: const Text('Favorites')),
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
                    : 'Favorites are unavailable.',
                onRetry: _refresh,
              );
            }
            final stations = snapshot.data ?? const [];
            if (stations.isEmpty) {
              return _FavoriteMessage(
                message: 'No favorite stations yet.',
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
                      subtitle: Text(
                        '${station.river} • ${station.level.toStringAsFixed(0)} cm',
                      ),
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
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Refresh')),
      ],
    ),
  );
}
