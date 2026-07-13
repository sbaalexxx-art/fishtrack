import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/station.dart';
import '../core/cache/timed_cache.dart';
import '../models/water_level.dart';
import '../repositories/water_repository.dart';
import 'location_service.dart';

enum WaterUiStatus {
  availableHistory,
  insufficientHistory,
  providerError,
  unavailable,
}

class WaterUiResult {
  const WaterUiResult({
    required this.latestReading,
    required this.history,
    required this.source,
    required this.sourceName,
    required this.measurementTimestamp,
    required this.dataAge,
    required this.isStale,
    required this.status,
    required this.safeDiagnosticMessage,
  });

  final WaterLevel? latestReading;
  final List<WaterLevel> history;
  final WaterLevelSource? source;
  final String? sourceName;
  final DateTime? measurementTimestamp;
  final Duration? dataAge;
  final bool isStale;
  final WaterUiStatus status;
  final String? safeDiagnosticMessage;
}

class _WaterUiCacheEntry {
  const _WaterUiCacheEntry({required this.result, required this.savedAt});

  final WaterUiResult result;
  final DateTime savedAt;
}

class WaterService {
  WaterService({WaterRepository? repository, LocationService? locationService})
    : _repository = repository ?? const WaterRepository(),
      _locationService = locationService ?? const LocationService();

  static const cacheDuration = Duration(minutes: 30);
  static final StreamController<Station> _stationSelectionController =
      StreamController<Station>.broadcast(sync: true);
  static final TimedCache<List<Station>> _stationsCache =
      TimedCache<List<Station>>(duration: cacheDuration);
  static final Map<String, TimedCache<List<WaterLevel>>> _historyCache = {};
  static final Map<String, _WaterUiCacheEntry> _waterUiCache = {};
  static final Map<String, Future<WaterUiResult>> _waterUiInFlight = {};
  static final Map<String, int> _waterUiKeyGenerations = {};
  static int _waterUiCacheEpoch = 0;
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
    _historyCache.clear();
    _waterUiCacheEpoch++;
    _waterUiCache.clear();
    _waterUiInFlight.clear();
    _waterUiKeyGenerations.clear();
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
  }) async {
    final key = '$stationId:${stationName ?? ''}:$limit';
    final cache = _historyCache.putIfAbsent(
      key,
      () => TimedCache<List<WaterLevel>>(duration: cacheDuration),
    );
    try {
      return (await cache.get(
        () async => List<WaterLevel>.unmodifiable(
          await _repository.getHistory(
            stationId,
            stationName: stationName,
            limit: limit,
          ),
        ),
      )).value;
    } on Exception {
      return const <WaterLevel>[];
    }
  }

  Future<WaterUiResult> getWaterUiResult(
    Station station, {
    int limit = 72,
    Duration historyWindow = const Duration(hours: 24),
    bool forceRefresh = false,
  }) {
    final key = _waterUiCacheKey(station, limit, historyWindow);
    final now = DateTime.now();
    if (forceRefresh) {
      _waterUiCache.remove(key);
      _waterUiInFlight.remove(key);
      _waterUiKeyGenerations[key] = (_waterUiKeyGenerations[key] ?? 0) + 1;
    } else {
      final cached = _waterUiCache[key];
      if (cached != null && now.difference(cached.savedAt) < cacheDuration) {
        return Future<WaterUiResult>.value(
          _withCurrentFreshness(cached.result, now),
        );
      }
      final activeRequest = _waterUiInFlight[key];
      if (activeRequest != null) return activeRequest;
    }

    final requestEpoch = _waterUiCacheEpoch;
    final requestGeneration = _waterUiKeyGenerations[key] ?? 0;
    late final Future<WaterUiResult> request;
    request =
        _loadWaterUiResult(station, limit: limit, historyWindow: historyWindow)
            .then((result) {
              if (_waterUiCacheEpoch == requestEpoch &&
                  (_waterUiKeyGenerations[key] ?? 0) == requestGeneration) {
                _waterUiCache[key] = _WaterUiCacheEntry(
                  result: result,
                  savedAt: DateTime.now(),
                );
              }
              return _withCurrentFreshness(result, DateTime.now());
            })
            .whenComplete(() {
              if (identical(_waterUiInFlight[key], request)) {
                _waterUiInFlight.remove(key);
              }
            });
    _waterUiInFlight[key] = request;
    return request;
  }

  Future<WaterUiResult> _loadWaterUiResult(
    Station station, {
    required int limit,
    required Duration historyWindow,
  }) async {
    final now = DateTime.now();
    final stationReading = _readingFromStation(station);
    late final WaterHistoryResult repositoryResult;
    try {
      repositoryResult = await _repository.getHistoryResult(
        station.id,
        stationName: station.name,
        limit: limit,
      );
    } on Exception {
      repositoryResult = const WaterHistoryResult(
        status: WaterHistoryResultStatus.providerError,
        readings: [],
        source: null,
        hadProviderError: true,
        safeDiagnosticMessage: 'Water history request failed',
      );
    }

    final cutoff = now.subtract(historyWindow);
    final validReadings =
        repositoryResult.readings
            .where(_isValidReading)
            .where((reading) => !reading.timestamp.isAfter(now))
            .toList(growable: false)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final selectedReading = _latestReadingByAuthority(
      stationReading,
      validReadings,
    );
    final compatibleReadings = selectedReading == null
        ? const <WaterLevel>[]
        : validReadings
              .where((reading) => reading.source == selectedReading.source)
              .where((reading) => !reading.timestamp.isBefore(cutoff))
              .toList(growable: false);
    final history = _withCompatibleTrends(compatibleReadings);
    final latestReading = selectedReading == null
        ? null
        : _withCompatibleTrend(selectedReading, compatibleReadings);
    final measurementTimestamp = latestReading?.timestamp;

    final status = history.length >= 2
        ? WaterUiStatus.availableHistory
        : latestReading != null
        ? WaterUiStatus.insufficientHistory
        : repositoryResult.status == WaterHistoryResultStatus.providerError
        ? WaterUiStatus.providerError
        : WaterUiStatus.unavailable;

    return WaterUiResult(
      latestReading: latestReading,
      history: List<WaterLevel>.unmodifiable(history),
      source: latestReading?.source ?? repositoryResult.source,
      sourceName: latestReading?.sourceName,
      measurementTimestamp: measurementTimestamp,
      dataAge: null,
      isStale: false,
      status: status,
      safeDiagnosticMessage: repositoryResult.safeDiagnosticMessage,
    );
  }

  Future<List<Station>> getStations({bool forceRefresh = false}) async =>
      (await getStationsResult(forceRefresh: forceRefresh)).value;

  Future<CacheResult<List<Station>>> getStationsResult({
    bool forceRefresh = false,
  }) async {
    try {
      return await _stationsCache.get(
        () async => List<Station>.unmodifiable(await _repository.getStations()),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      return const CacheResult<List<Station>>(<Station>[]);
    }
  }

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

  String _waterUiCacheKey(Station station, int limit, Duration historyWindow) {
    final measurementTimestamp = station.hasWaterLevel
        ? station.lastUpdate.microsecondsSinceEpoch
        : 'none';
    return '${identityHashCode(_repository)}:${station.id}:'
        '$measurementTimestamp:$limit:${historyWindow.inMicroseconds}';
  }

  static WaterUiResult _withCurrentFreshness(
    WaterUiResult result,
    DateTime now,
  ) {
    final timestamp = result.measurementTimestamp;
    final dataAge = timestamp == null ? null : _nonNegativeAge(now, timestamp);
    final isStale =
        dataAge != null && dataAge > WaterRepository.defaultFreshnessThreshold;
    return WaterUiResult(
      latestReading: result.latestReading,
      history: result.history,
      source: result.source,
      sourceName: result.sourceName,
      measurementTimestamp: timestamp,
      dataAge: dataAge,
      isStale: isStale,
      status: result.status,
      safeDiagnosticMessage: result.safeDiagnosticMessage,
    );
  }

  static WaterLevel? _readingFromStation(Station station) {
    if (!station.hasWaterLevel ||
        !station.level.isFinite ||
        station.lastUpdate.millisecondsSinceEpoch <= 0) {
      return null;
    }

    return WaterLevel(
      stationId: station.id,
      value: station.level,
      timestamp: station.lastUpdate,
      trend: station.trend,
      source: WaterLevelSource.parse(station.waterLevelSource),
      unit: station.waterLevelUnit,
      sourceName: station.waterLevelSource,
      hasKnownTrend: station.hasKnownTrend,
    );
  }

  static WaterLevel? _latestReadingByAuthority(
    WaterLevel? stationReading,
    List<WaterLevel> history,
  ) {
    final candidates = <WaterLevel>[
      if (stationReading != null && _isValidReading(stationReading))
        stationReading,
      ...history.where(_isValidReading),
    ];
    if (candidates.isEmpty) return null;

    final official = candidates.where(
      (reading) => _isOfficialSource(reading.source),
    );
    final authoritativeCandidates = official.isEmpty ? candidates : official;
    return authoritativeCandidates.reduce(
      (current, candidate) =>
          candidate.timestamp.isAfter(current.timestamp) ? candidate : current,
    );
  }

  static List<WaterLevel> _withCompatibleTrends(List<WaterLevel> readings) {
    return List<WaterLevel>.unmodifiable(
      List.generate(
        readings.length,
        (index) => _copyWithTrend(
          readings[index],
          index == 0 ? null : readings[index - 1],
        ),
        growable: false,
      ),
    );
  }

  static WaterLevel _withCompatibleTrend(
    WaterLevel reading,
    List<WaterLevel> compatibleHistory,
  ) {
    WaterLevel? previous;
    for (final candidate in compatibleHistory.reversed) {
      if (candidate.timestamp.isBefore(reading.timestamp)) {
        previous = candidate;
        break;
      }
    }
    return _copyWithTrend(reading, previous);
  }

  static WaterLevel _copyWithTrend(WaterLevel reading, WaterLevel? previous) {
    if (previous == null || previous.source != reading.source) {
      return WaterLevel(
        stationId: reading.stationId,
        value: reading.value,
        timestamp: reading.timestamp,
        trend: WaterTrend.stable,
        source: reading.source,
        unit: reading.unit,
        sourceName: reading.sourceName,
        hasKnownTrend: false,
      );
    }

    final difference = reading.value - previous.value;
    final trend = difference.abs() <= .01
        ? WaterTrend.stable
        : difference > 0
        ? WaterTrend.rising
        : WaterTrend.falling;
    return WaterLevel(
      stationId: reading.stationId,
      value: reading.value,
      timestamp: reading.timestamp,
      trend: trend,
      source: reading.source,
      unit: reading.unit,
      sourceName: reading.sourceName,
      hasKnownTrend: true,
    );
  }

  static bool _isOfficialSource(WaterLevelSource source) => switch (source) {
    WaterLevelSource.afdj ||
    WaterLevelSource.danubeHis ||
    WaterLevelSource.danubeFis => true,
    WaterLevelSource.inhga || WaterLevelSource.manualFallback => false,
  };

  static bool _isValidReading(WaterLevel reading) =>
      reading.value.isFinite && reading.timestamp.millisecondsSinceEpoch > 0;

  static Duration _nonNegativeAge(DateTime now, DateTime timestamp) {
    final age = now.difference(timestamp.toLocal());
    return age.isNegative ? Duration.zero : age;
  }
}
