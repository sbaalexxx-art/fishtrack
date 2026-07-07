import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/station.dart';
import '../core/cache/timed_cache.dart';
import '../models/water_level.dart';
import '../repositories/water_repository.dart';
import 'location_service.dart';

class WaterService {
  WaterService({WaterRepository? repository, LocationService? locationService})
    : _repository = repository ?? const WaterRepository(),
      _locationService = locationService ?? const LocationService();

  static const cacheDuration = Duration(minutes: 30);
  static final StreamController<Station> _stationSelectionController =
      StreamController<Station>.broadcast(sync: true);
  static final TimedCache<List<Station>> _stationsCache =
      TimedCache<List<Station>>(duration: cacheDuration);
  static Station? _selectedStation;

  final WaterRepository _repository;
  final LocationService _locationService;

  static const supportedSources = <WaterLevelSource>{
    WaterLevelSource.afdj,
    WaterLevelSource.danubeHis,
    WaterLevelSource.danubeFis,
    WaterLevelSource.inhga,
    WaterLevelSource.manualFallback,
  };

  WaterLevelSource get activeSource => _repository.source;

  static void clearCache() {
    _stationsCache.clear();
  }

  Stream<Station> get stationSelections => _stationSelectionController.stream;
  Station? get selectedStation => _selectedStation;

  void selectStation(Station station) {
    _selectedStation = station;
    _stationSelectionController.add(station);
  }

  Future<List<WaterLevel>> getHistory(
    String stationId, {
    String? stationName,
    int limit = 14,
  }) =>
      _repository.getHistory(stationId, stationName: stationName, limit: limit);

  Future<List<Station>> getStations({bool forceRefresh = false}) async =>
      (await getStationsResult(forceRefresh: forceRefresh)).value;

  Future<CacheResult<List<Station>>> getStationsResult({
    bool forceRefresh = false,
  }) => _stationsCache.get(
    () async => List<Station>.unmodifiable(await _repository.getStations()),
    forceRefresh: forceRefresh,
  );

  Future<Station?> getNearestStation({Station? fallbackStation}) async {
    final stations = await getStations();
    if (stations.isEmpty) {
      return null;
    }

    try {
      final position = await _locationService.determinePosition();
      return stations.reduce((nearest, candidate) {
        final nearestDistance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          nearest.latitude,
          nearest.longitude,
        );
        final candidateDistance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          candidate.latitude,
          candidate.longitude,
        );
        return candidateDistance < nearestDistance ? candidate : nearest;
      });
    } on LocationFailure {
      final selected = fallbackStation ?? _selectedStation;
      if (selected == null) {
        return stations.first;
      }

      for (final station in stations) {
        if (station.id == selected.id) {
          return station;
        }
      }
      return selected;
    }
  }
}
