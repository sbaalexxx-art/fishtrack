import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

enum WaterStationSelectionMode { automatic, pinned }

class WaterHomeStationSelection {
  const WaterHomeStationSelection({
    required this.mode,
    required this.station,
    required this.candidates,
    this.canonicalStations = const <Station>[],
  });

  final WaterStationSelectionMode mode;
  final Station? station;
  final List<Station> candidates;
  final List<Station> canonicalStations;
}

class WaterHomeCachedSnapshot {
  const WaterHomeCachedSnapshot({
    required this.station,
    required this.result,
    required this.savedAt,
  });

  final Station station;
  final WaterUiResult result;
  final DateTime savedAt;
}

enum WaterStationDetailsRange {
  sevenDays(Duration(days: 7)),
  thirtyDays(Duration(days: 30));

  const WaterStationDetailsRange(this.duration);

  final Duration duration;
  int get historyLimit => duration.inHours + 1;
}

enum WaterStationDetailsHistoryStatus {
  available,
  insufficientHistory,
  providerError,
  unavailable,
}

class WaterStationDetailsResult {
  const WaterStationDetailsResult({
    required this.currentReading,
    required this.source,
    required this.sourceName,
    required this.measurementTimestamp,
    required this.dataAge,
    required this.isStale,
    required this.history,
    required this.selectedRange,
    required this.historyStatus,
    required this.dailyDeltaCm,
    required this.trend,
    required this.safeDiagnosticMessage,
  });

  final WaterLevel? currentReading;
  final WaterLevelSource? source;
  final String? sourceName;
  final DateTime? measurementTimestamp;
  final Duration? dataAge;
  final bool isStale;
  final List<WaterLevel> history;
  final WaterStationDetailsRange selectedRange;
  final WaterStationDetailsHistoryStatus historyStatus;
  final double? dailyDeltaCm;
  final WaterTrend? trend;
  final String? safeDiagnosticMessage;
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
    this.previousReading,
    this.deltaCm,
    this.comparisonDuration,
    this.trend,
    this.hasEnoughHistory = false,
    this.providerError = false,
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
  final WaterLevel? previousReading;
  final double? deltaCm;
  final Duration? comparisonDuration;
  final WaterTrend? trend;
  final bool hasEnoughHistory;
  final bool providerError;
}

class WaterStationBatchResult {
  const WaterStationBatchResult({
    required this.stations,
    required this.resultsByStationId,
    required this.totalStationCount,
    required this.stationWithReadingCount,
    required this.stationWithoutDataCount,
    required this.providerErrorCount,
    required this.latestMeasurementTimestamp,
    required this.isStationListStaleFallback,
    required this.stationListLoadFailed,
    required this.safeDiagnosticMessage,
    this.isComplete = true,
  });

  final List<Station> stations;
  final Map<String, WaterUiResult> resultsByStationId;
  final int totalStationCount;
  final int stationWithReadingCount;
  final int stationWithoutDataCount;
  final int providerErrorCount;
  final DateTime? latestMeasurementTimestamp;
  final bool isStationListStaleFallback;
  final bool stationListLoadFailed;
  final String? safeDiagnosticMessage;
  final bool isComplete;

  int get loadedStationCount => resultsByStationId.length;
  int get pendingStationCount => totalStationCount - loadedStationCount;
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
  static const homeRotationInterval = Duration(seconds: 12);
  static const _maxBatchConcurrency = 4;
  static const _selectionModeKey = 'water_home_station_selection_mode';
  static const _pinnedStationIdKey = 'water_home_pinned_station_id';
  static const _homeSnapshotKey = 'water_home_last_valid_snapshot_v1';
  static const _homeSnapshotSchemaVersion = 1;
  static const _maxPersistedHomeHistoryPoints = 30;
  static final StreamController<Station> _stationSelectionController =
      StreamController<Station>.broadcast(sync: true);
  static final TimedCache<List<Station>> _stationsCache =
      TimedCache<List<Station>>(duration: cacheDuration);
  static final TimedCache<List<Station>> _fastStationsCache =
      TimedCache<List<Station>>(duration: cacheDuration);
  static final Map<String, TimedCache<List<WaterLevel>>> _historyCache = {};
  static final Map<String, _WaterUiCacheEntry> _waterUiCache = {};
  static final Map<String, WaterUiResult> _lastKnownGoodByStation = {};
  static final Map<String, Future<WaterUiResult>> _waterUiInFlight = {};
  static final Map<String, int> _waterUiKeyGenerations = {};
  static int _waterUiCacheEpoch = 0;
  static int _progressiveBatchGeneration = 0;
  static Station? _selectedStation;
  static Station? _lastAutomaticStation;
  static WaterStationSelectionMode _selectionMode =
      WaterStationSelectionMode.automatic;
  static Future<void>? _selectionRestore;
  static bool _selectionWasExplicitlySet = false;

  final WaterRepository _repository;
  final LocationService _locationService;
  Future<WaterHomeCachedSnapshot?>? _persistedHomeSnapshotRestore;
  String? _lastPersistedHomeSnapshotSignature;

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
    _fastStationsCache.clear();
    _historyCache.clear();
    _waterUiCacheEpoch++;
    _waterUiCache.clear();
    _lastKnownGoodByStation.clear();
    _waterUiInFlight.clear();
    _waterUiKeyGenerations.clear();
  }

  Stream<Station> get stationSelections => _stationSelectionController.stream;
  Station? get selectedStation => _selectedStation;
  Station? get lastAutomaticStation => _lastAutomaticStation;
  WaterStationSelectionMode get selectionMode => _selectionMode;

  Future<WaterHomeCachedSnapshot?> restorePersistedHomeSnapshot() {
    return _persistedHomeSnapshotRestore ??= _restorePersistedHomeSnapshot();
  }

  void selectStation(Station station) {
    _selectedStation = station;
    _selectionMode = WaterStationSelectionMode.pinned;
    _selectionWasExplicitlySet = true;
    unawaited(_persistPinnedStation(station.id));
    _stationSelectionController.add(station);
  }

  Future<void> setAutomatic() async {
    _selectedStation = null;
    _selectionMode = WaterStationSelectionMode.automatic;
    _selectionWasExplicitlySet = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectionModeKey, 'automatic');
    await preferences.remove(_pinnedStationIdKey);
  }

  Future<void> clearSelection() => setAutomatic();

  Future<WaterHomeStationSelection> resolveHomeStationSelection() async {
    await _restoreSelection();
    final stations = await getStations();
    final canonicalStations = orderCanonicalStations(stations);

    if (_selectionMode == WaterStationSelectionMode.pinned) {
      final pinned = _selectedStation;
      final restored = pinned == null
          ? null
          : canonicalStations
                .where((station) => station.id == pinned.id)
                .firstOrNull;
      if (restored != null) {
        _selectedStation = restored;
        return WaterHomeStationSelection(
          mode: _selectionMode,
          station: restored,
          candidates: rankHomeCandidates(stations),
          canonicalStations: canonicalStations,
        );
      }
      await setAutomatic();
    }

    try {
      final position = await _locationService.determinePosition();
      final candidates = rankHomeCandidates(
        stations,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final automaticStations = rankCanonicalStations(
        canonicalStations,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final automaticStation = automaticStations.firstOrNull;
      if (automaticStation != null) {
        _lastAutomaticStation = automaticStation;
      }
      return WaterHomeStationSelection(
        mode: WaterStationSelectionMode.automatic,
        station: automaticStation,
        candidates: candidates,
        canonicalStations: canonicalStations,
      );
    } on LocationFailure {
      // Without a real position there is no safe automatic station choice.
    } on Exception {
      // Keep automatic mode without inventing a first-station fallback.
    }

    final retainedAutomaticStation = _lastAutomaticStation == null
        ? null
        : canonicalStations
              .where((station) => station.id == _lastAutomaticStation!.id)
              .firstOrNull;
    if (retainedAutomaticStation != null) {
      _lastAutomaticStation = retainedAutomaticStation;
    }
    return WaterHomeStationSelection(
      mode: WaterStationSelectionMode.automatic,
      station: retainedAutomaticStation,
      candidates: rankHomeCandidates(stations),
      canonicalStations: canonicalStations,
    );
  }

  static List<String> get canonicalStationNames =>
      WaterRepository.officialAfdjStationOrder;

  static List<Station> orderCanonicalStations(Iterable<Station> stations) {
    final byName = <String, Station>{
      for (final station in stations)
        _normalizeStationName(station.name): station,
    };
    return List<Station>.unmodifiable(
      canonicalStationNames
          .map((name) => byName[_normalizeStationName(name)])
          .whereType<Station>(),
    );
  }

  static List<String> filterCanonicalStationNames(String query) {
    final normalizedQuery = _normalizeStationName(query);
    if (normalizedQuery.isEmpty) return canonicalStationNames;
    return List<String>.unmodifiable(
      canonicalStationNames.where(
        (name) => _normalizeStationName(name).contains(normalizedQuery),
      ),
    );
  }

  static Station? canonicalStationNamed(
    Iterable<Station> stations,
    String canonicalName,
  ) {
    final normalizedName = _normalizeStationName(canonicalName);
    return stations
        .where(
          (station) => _normalizeStationName(station.name) == normalizedName,
        )
        .firstOrNull;
  }

  static List<Station> rankCanonicalStations(
    Iterable<Station> stations, {
    required double latitude,
    required double longitude,
  }) {
    final canonicalOrder = canonicalStationNames
        .map(_normalizeStationName)
        .toList(growable: false);
    final ranked = orderCanonicalStations(stations)
        .where(
          (station) =>
              station.latitude.isFinite &&
              station.longitude.isFinite &&
              station.latitude.abs() <= 90 &&
              station.longitude.abs() <= 180 &&
              (station.latitude != 0 || station.longitude != 0),
        )
        .toList();
    ranked.sort((left, right) {
      final leftDistance = Geolocator.distanceBetween(
        latitude,
        longitude,
        left.latitude,
        left.longitude,
      );
      final rightDistance = Geolocator.distanceBetween(
        latitude,
        longitude,
        right.latitude,
        right.longitude,
      );
      final byDistance = leftDistance.compareTo(rightDistance);
      if (byDistance != 0) return byDistance;
      return canonicalOrder
          .indexOf(_normalizeStationName(left.name))
          .compareTo(canonicalOrder.indexOf(_normalizeStationName(right.name)));
    });
    return List<Station>.unmodifiable(ranked);
  }

  static List<Station> eligibleHomeStations(Iterable<Station> stations) {
    final canonicalNames = WaterRepository.officialAfdjStationOrder
        .map(_normalizeStationName)
        .toSet();
    final seenIds = <String>{};
    return stations
        .where(
          (station) =>
              station.id.trim().isNotEmpty &&
              seenIds.add(station.id) &&
              canonicalNames.contains(_normalizeStationName(station.name)) &&
              station.latitude.isFinite &&
              station.longitude.isFinite &&
              station.latitude.abs() <= 90 &&
              station.longitude.abs() <= 180 &&
              station.hasWaterLevel &&
              station.level.isFinite,
        )
        .toList(growable: false);
  }

  static List<Station> rankHomeCandidates(
    Iterable<Station> stations, {
    double? latitude,
    double? longitude,
  }) {
    final candidates = eligibleHomeStations(stations).toList();
    final canonicalOrder = WaterRepository.officialAfdjStationOrder
        .map(_normalizeStationName)
        .toList();
    candidates.sort((left, right) {
      if (latitude != null && longitude != null) {
        final leftDistance = Geolocator.distanceBetween(
          latitude,
          longitude,
          left.latitude,
          left.longitude,
        );
        final rightDistance = Geolocator.distanceBetween(
          latitude,
          longitude,
          right.latitude,
          right.longitude,
        );
        final byDistance = leftDistance.compareTo(rightDistance);
        if (byDistance != 0) return byDistance;
      }
      final leftOrder = canonicalOrder.indexOf(
        _normalizeStationName(left.name),
      );
      final rightOrder = canonicalOrder.indexOf(
        _normalizeStationName(right.name),
      );
      return leftOrder != rightOrder
          ? leftOrder.compareTo(rightOrder)
          : left.name.compareTo(right.name);
    });

    if (latitude == null || longitude == null) {
      final baziasIndex = candidates.indexWhere(
        (station) => _normalizeStationName(station.name) == 'bazias',
      );
      if (baziasIndex == 0 && candidates.length > 1) {
        candidates.add(candidates.removeAt(0));
      }
    }
    return List<Station>.unmodifiable(candidates.take(5));
  }

  static void resetStationSelectionForTest() {
    _selectedStation = null;
    _lastAutomaticStation = null;
    _selectionMode = WaterStationSelectionMode.automatic;
    _selectionRestore = null;
    _selectionWasExplicitlySet = false;
  }

  Future<void> _restoreSelection() {
    return _selectionRestore ??= () async {
      final preferences = await SharedPreferences.getInstance();
      if (_selectionWasExplicitlySet) return;
      final savedMode = preferences.getString(_selectionModeKey);
      final pinnedId = preferences.getString(_pinnedStationIdKey);
      if (savedMode == 'pinned' && pinnedId != null && pinnedId.isNotEmpty) {
        _selectionMode = WaterStationSelectionMode.pinned;
        _selectedStation = Station(
          id: pinnedId,
          name: '',
          river: '',
          level: double.nan,
          trend: WaterTrend.stable,
          latitude: 0,
          longitude: 0,
          lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      } else {
        _selectionMode = WaterStationSelectionMode.automatic;
        _selectedStation = null;
      }
    }();
  }

  Future<void> _persistPinnedStation(String stationId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectionModeKey, 'pinned');
    await preferences.setString(_pinnedStationIdKey, stationId);
  }

  Future<WaterHomeCachedSnapshot?> _restorePersistedHomeSnapshot() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_homeSnapshotKey);
    if (encoded == null || encoded.trim().isEmpty) return null;

    try {
      final payload = _stringKeyedMap(jsonDecode(encoded));
      final schemaVersion = payload?['schema_version'];
      final savedAt = DateTime.tryParse(payload?['saved_at']?.toString() ?? '');
      final stationMap = _stringKeyedMap(payload?['station']);
      final resultMap = _stringKeyedMap(payload?['result']);
      if (payload == null ||
          schemaVersion is! num ||
          schemaVersion.toInt() != _homeSnapshotSchemaVersion ||
          savedAt == null ||
          stationMap == null ||
          resultMap == null) {
        await preferences.remove(_homeSnapshotKey);
        return null;
      }

      final now = DateTime.now();
      if (savedAt.isAfter(now.add(const Duration(minutes: 5)))) {
        await preferences.remove(_homeSnapshotKey);
        return null;
      }

      final station = Station.tryFromJson(stationMap);
      if (station == null ||
          !station.hasWaterLevel ||
          !station.level.isFinite ||
          station.lastUpdate.millisecondsSinceEpoch <= 0) {
        await preferences.remove(_homeSnapshotKey);
        return null;
      }

      final restored = _waterUiResultFromPersistedMap(
        resultMap,
        stationId: station.id,
      );
      if (restored == null || !_hasValidReading(restored)) {
        await preferences.remove(_homeSnapshotKey);
        return null;
      }

      final result = _withCurrentFreshness(restored, now);
      await _restoreSelection();
      if (_selectionMode == WaterStationSelectionMode.pinned &&
          _selectedStation?.id == station.id) {
        _selectedStation = station;
      } else if (_selectionMode == WaterStationSelectionMode.automatic) {
        _lastAutomaticStation = station;
      }

      _lastKnownGoodByStation[_lastKnownGoodKey(station)] = result;
      final cacheAge = now.difference(savedAt);
      if (!cacheAge.isNegative && cacheAge < cacheDuration) {
        _waterUiCache[_waterUiCacheKey(
          station,
          72,
          const Duration(hours: 24),
        )] = _WaterUiCacheEntry(
          result: result,
          savedAt: savedAt,
        );
      }
      _lastPersistedHomeSnapshotSignature = _homeSnapshotSignature(
        station,
        result,
      );

      return WaterHomeCachedSnapshot(
        station: station,
        result: result,
        savedAt: savedAt,
      );
    } on FormatException {
      await preferences.remove(_homeSnapshotKey);
      return null;
    } on Exception {
      return null;
    }
  }

  Future<void> _persistHomeSnapshot(
    Station station,
    WaterUiResult result,
  ) async {
    if (!_shouldPersistHomeSnapshot(station) || !_hasValidReading(result)) {
      return;
    }

    final latest = result.latestReading!;
    if (!_isOfficialSource(latest.source) ||
        latest.unit.trim().toLowerCase() != 'cm' ||
        station.id.trim().isEmpty ||
        station.name.trim().isEmpty ||
        !station.latitude.isFinite ||
        !station.longitude.isFinite ||
        station.latitude.abs() > 90 ||
        station.longitude.abs() > 180) {
      return;
    }

    final signature = _homeSnapshotSignature(station, result);
    if (signature == _lastPersistedHomeSnapshotSignature) return;

    final historyByTimestamp = <int, WaterLevel>{};
    for (final reading in result.history) {
      if (!_isValidReading(reading) ||
          reading.stationId != station.id ||
          reading.unit.trim().toLowerCase() != 'cm' ||
          !_isOfficialSource(reading.source) ||
          !_sourcesCanShareHistory(reading.source, latest.source) ||
          reading.timestamp.isAfter(latest.timestamp)) {
        continue;
      }
      historyByTimestamp[reading.timestamp.toUtc().microsecondsSinceEpoch] =
          reading;
    }
    historyByTimestamp[latest.timestamp.toUtc().microsecondsSinceEpoch] =
        latest;
    final chronological = historyByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final persistedHistory =
        chronological.length <= _maxPersistedHomeHistoryPoints
        ? chronological
        : chronological.sublist(
            chronological.length - _maxPersistedHomeHistoryPoints,
          );

    final payload = <String, Object?>{
      'schema_version': _homeSnapshotSchemaVersion,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'station': _stationToPersistedMap(station, latest),
      'result': <String, Object?>{
        'latest_reading': _waterLevelToPersistedMap(latest),
        'history': persistedHistory
            .map(_waterLevelToPersistedMap)
            .toList(growable: false),
        'source': (result.source ?? latest.source).name,
        'source_name': result.sourceName ?? latest.sourceName,
        'measurement_timestamp': latest.timestamp.toUtc().toIso8601String(),
        'previous_reading': result.previousReading == null
            ? null
            : _waterLevelToPersistedMap(result.previousReading!),
        'delta_cm': result.deltaCm,
        'comparison_duration_microseconds':
            result.comparisonDuration?.inMicroseconds,
        'trend': result.trend?.name,
        'has_enough_history': result.hasEnoughHistory,
      },
    };

    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _homeSnapshotKey,
        jsonEncode(payload),
      );
      if (saved) _lastPersistedHomeSnapshotSignature = signature;
    } catch (_) {
      // Persistence is an optimization. Live water loading remains authoritative.
    }
  }

  bool _shouldPersistHomeSnapshot(Station station) {
    if (_selectionMode == WaterStationSelectionMode.pinned) {
      return _selectedStation?.id == station.id;
    }
    return _lastAutomaticStation == null ||
        _lastAutomaticStation?.id == station.id;
  }

  String _homeSnapshotSignature(Station station, WaterUiResult result) {
    final latest = result.latestReading!;
    final lastHistoryTimestamp = result.history.isEmpty
        ? latest.timestamp
        : result.history.last.timestamp;
    return '${station.id}:${latest.timestamp.toUtc().microsecondsSinceEpoch}:'
        '${latest.value}:${latest.source.name}:${result.history.length}:'
        '${lastHistoryTimestamp.toUtc().microsecondsSinceEpoch}';
  }

  static Map<String, dynamic>? _stringKeyedMap(Object? value) {
    if (value is! Map) return null;
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      return null;
    }
  }

  static Map<String, Object?> _stationToPersistedMap(
    Station station,
    WaterLevel latest,
  ) {
    return <String, Object?>{
      'id': station.id,
      'name': station.name,
      'river': station.river,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'level': latest.value,
      'trend': latest.trend.name,
      'last_update': latest.timestamp.toUtc().toIso8601String(),
      'water_type': station.waterBodyType.name,
      'species': station.species,
      'difficulty': station.difficulty.name,
      'is_favorite': station.isFavorite,
      'has_water_level': true,
      'has_known_trend': latest.hasKnownTrend,
      'water_level_unit': latest.unit,
      'water_level_source': latest.source.name,
    };
  }

  static Map<String, Object?> _waterLevelToPersistedMap(WaterLevel reading) {
    return <String, Object?>{
      'station_id': reading.stationId,
      'value': reading.value,
      'timestamp': reading.timestamp.toUtc().toIso8601String(),
      'trend': reading.trend.name,
      'source': reading.source.name,
      'unit': reading.unit,
      'source_name': reading.sourceName,
      'has_known_trend': reading.hasKnownTrend,
    };
  }

  static WaterUiResult? _waterUiResultFromPersistedMap(
    Map<String, dynamic> map, {
    required String stationId,
  }) {
    final latest = _waterLevelFromPersistedMap(
      map['latest_reading'],
      stationId: stationId,
    );
    if (latest == null ||
        !_isOfficialSource(latest.source) ||
        latest.unit.trim().toLowerCase() != 'cm') {
      return null;
    }

    final historyByTimestamp = <int, WaterLevel>{};
    final rawHistory = map['history'];
    if (rawHistory is Iterable) {
      for (final rawReading in rawHistory) {
        final reading = _waterLevelFromPersistedMap(
          rawReading,
          stationId: stationId,
        );
        if (reading == null ||
            !_isOfficialSource(reading.source) ||
            reading.unit.trim().toLowerCase() != 'cm' ||
            !_sourcesCanShareHistory(reading.source, latest.source) ||
            reading.timestamp.isAfter(latest.timestamp)) {
          continue;
        }
        historyByTimestamp[reading.timestamp.toUtc().microsecondsSinceEpoch] =
            reading;
      }
    }
    historyByTimestamp[latest.timestamp.toUtc().microsecondsSinceEpoch] =
        latest;
    final chronological = historyByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final history = chronological.length <= _maxPersistedHomeHistoryPoints
        ? chronological
        : chronological.sublist(
            chronological.length - _maxPersistedHomeHistoryPoints,
          );

    WaterLevel? previous = _waterLevelFromPersistedMap(
      map['previous_reading'],
      stationId: stationId,
    );
    if (previous == null ||
        !previous.timestamp.isBefore(latest.timestamp) ||
        !_sourcesCanShareHistory(previous.source, latest.source)) {
      previous = null;
      for (final candidate in history.reversed) {
        if (candidate.timestamp.isBefore(latest.timestamp) &&
            _sourcesCanShareHistory(candidate.source, latest.source)) {
          previous = candidate;
          break;
        }
      }
    }

    final persistedDelta = map['delta_cm'];
    final deltaCm = persistedDelta is num && persistedDelta.toDouble().isFinite
        ? persistedDelta.toDouble()
        : previous == null
        ? null
        : latest.value - previous.value;
    final persistedDuration = map['comparison_duration_microseconds'];
    final comparisonDuration =
        persistedDuration is num && persistedDuration.toInt() > 0
        ? Duration(microseconds: persistedDuration.toInt())
        : previous == null
        ? null
        : latest.timestamp.difference(previous.timestamp);
    final persistedTrend = _waterTrendFromName(map['trend']);
    final source = WaterLevelSource.parse(
      map['source'],
      fallback: latest.source,
    );
    final sourceName = map['source_name']?.toString().trim();

    return WaterUiResult(
      latestReading: latest,
      history: List<WaterLevel>.unmodifiable(history),
      source: source,
      sourceName: sourceName == null || sourceName.isEmpty
          ? latest.sourceName
          : sourceName,
      measurementTimestamp: latest.timestamp,
      dataAge: null,
      isStale: false,
      status: history.length >= 2
          ? WaterUiStatus.availableHistory
          : WaterUiStatus.insufficientHistory,
      safeDiagnosticMessage: null,
      previousReading: previous,
      deltaCm: deltaCm,
      comparisonDuration: comparisonDuration,
      trend: persistedTrend ?? (latest.hasKnownTrend ? latest.trend : null),
      hasEnoughHistory: previous != null,
      providerError: false,
    );
  }

  static WaterLevel? _waterLevelFromPersistedMap(
    Object? raw, {
    required String stationId,
  }) {
    final map = _stringKeyedMap(raw);
    if (map == null) return null;

    final readingStationId = map['station_id']?.toString().trim();
    final value = map['value'] is num
        ? (map['value'] as num).toDouble()
        : double.tryParse(map['value']?.toString() ?? '');
    final timestamp = DateTime.tryParse(map['timestamp']?.toString() ?? '');
    final unit = map['unit']?.toString().trim();
    final source = WaterLevelSource.parse(map['source']);
    final parsedTrend = _waterTrendFromName(map['trend']);
    final hasKnownTrend = map['has_known_trend'] == true && parsedTrend != null;
    final sourceName = map['source_name']?.toString().trim();

    if (readingStationId != stationId ||
        value == null ||
        !value.isFinite ||
        timestamp == null ||
        unit == null ||
        unit.isEmpty) {
      return null;
    }

    final reading = WaterLevel(
      stationId: stationId,
      value: value,
      timestamp: timestamp,
      trend: parsedTrend ?? WaterTrend.stable,
      source: source,
      unit: unit,
      sourceName: sourceName == null || sourceName.isEmpty
          ? _canonicalSourceName(source)
          : sourceName,
      hasKnownTrend: hasKnownTrend,
    );
    return _isValidReading(reading) ? reading : null;
  }

  static WaterTrend? _waterTrendFromName(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'rising' => WaterTrend.rising,
      'falling' => WaterTrend.falling,
      'stable' => WaterTrend.stable,
      _ => null,
    };
  }

  static String _normalizeStationName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ă', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ș', 's')
      .replaceAll('ş', 's')
      .replaceAll('ț', 't')
      .replaceAll('ţ', 't');

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

  Future<WaterStationDetailsResult> getStationDetailsResult(
    Station station, {
    WaterStationDetailsRange range = WaterStationDetailsRange.sevenDays,
    bool forceRefresh = false,
  }) async {
    final currentResult = await getWaterUiResult(
      station,
      limit: 72,
      historyWindow: const Duration(hours: 24),
      forceRefresh: forceRefresh,
    );
    final current = currentResult.latestReading;
    final source = currentResult.source ?? current?.source;
    if (current == null || source == null || !_isValidReading(current)) {
      return WaterStationDetailsResult(
        currentReading: null,
        source: source,
        sourceName: currentResult.sourceName,
        measurementTimestamp: currentResult.measurementTimestamp,
        dataAge: currentResult.dataAge,
        isStale: currentResult.isStale,
        history: const <WaterLevel>[],
        selectedRange: range,
        historyStatus: currentResult.status == WaterUiStatus.providerError
            ? WaterStationDetailsHistoryStatus.providerError
            : WaterStationDetailsHistoryStatus.unavailable,
        dailyDeltaCm: null,
        trend: null,
        safeDiagnosticMessage: currentResult.safeDiagnosticMessage,
      );
    }

    final rangeStart = current.timestamp.subtract(range.duration);
    final currentTimestamp = current.timestamp.toUtc().microsecondsSinceEpoch;
    final readingsByTimestamp = <int, WaterLevel>{};
    for (final reading in currentResult.history) {
      if (!_isValidReading(reading) || reading.source != source) continue;
      if (reading.timestamp.isBefore(rangeStart)) continue;
      if (reading.timestamp.isAfter(current.timestamp)) continue;
      readingsByTimestamp[reading.timestamp.toUtc().microsecondsSinceEpoch] =
          reading;
    }
    readingsByTimestamp[currentTimestamp] = current;
    final history = readingsByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final hasTrend = history.length >= 2;
    final previous = hasTrend ? history[history.length - 2] : null;
    final dailyDeltaCm = previous == null
        ? null
        : current.value - previous.value;
    final trend = previous == null
        ? null
        : _copyWithTrend(current, previous).trend;

    return WaterStationDetailsResult(
      currentReading: current,
      source: source,
      sourceName: currentResult.sourceName ?? _canonicalSourceName(source),
      measurementTimestamp: currentResult.measurementTimestamp,
      dataAge: currentResult.dataAge,
      isStale: currentResult.isStale,
      history: List<WaterLevel>.unmodifiable(history),
      selectedRange: range,
      historyStatus: _stationDetailsHistoryStatus(
        currentResult,
        pointCount: history.length,
      ),
      dailyDeltaCm: dailyDeltaCm,
      trend: trend,
      safeDiagnosticMessage: currentResult.safeDiagnosticMessage,
    );
  }

  static WaterStationDetailsHistoryStatus _stationDetailsHistoryStatus(
    WaterUiResult result, {
    required int pointCount,
  }) {
    if (result.providerError || result.status == WaterUiStatus.providerError) {
      return WaterStationDetailsHistoryStatus.providerError;
    }
    if (pointCount < 2) {
      return pointCount == 0
          ? WaterStationDetailsHistoryStatus.unavailable
          : WaterStationDetailsHistoryStatus.insufficientHistory;
    }
    return WaterStationDetailsHistoryStatus.available;
  }

  static String _canonicalSourceName(WaterLevelSource source) =>
      switch (source) {
        WaterLevelSource.afdj => 'AFDJ',
        WaterLevelSource.danubeHis => 'DanubeHIS',
        WaterLevelSource.danubeFis => 'DanubeFIS',
        WaterLevelSource.inhga => 'INHGA',
        WaterLevelSource.manualFallback => 'Manual',
      };

  Future<WaterUiResult> getWaterUiResult(
    Station station, {
    int limit = 72,
    Duration historyWindow = const Duration(hours: 24),
    bool forceRefresh = false,
  }) {
    final key = _waterUiCacheKey(station, limit, historyWindow);
    final now = DateTime.now();
    final activeRequest = _waterUiInFlight[key];
    if (activeRequest != null) return activeRequest;

    if (forceRefresh) {
      _waterUiCache.remove(key);
      _waterUiKeyGenerations[key] = (_waterUiKeyGenerations[key] ?? 0) + 1;
    } else {
      final cached = _waterUiCache[key];
      if (cached != null && now.difference(cached.savedAt) < cacheDuration) {
        final resolved = _resolveWithLastKnownGood(
          station,
          cached.result,
          canUpdateLastKnownGood: true,
        );
        return Future<WaterUiResult>.value(
          _withCurrentFreshness(resolved, now),
        );
      }
    }

    final requestEpoch = _waterUiCacheEpoch;
    final requestGeneration = _waterUiKeyGenerations[key] ?? 0;
    late final Future<WaterUiResult> request;
    request =
        _loadWaterUiResult(station, limit: limit, historyWindow: historyWindow)
            .then((result) {
              final canCommit =
                  _waterUiCacheEpoch == requestEpoch &&
                  (_waterUiKeyGenerations[key] ?? 0) == requestGeneration;
              final resolved = _resolveWithLastKnownGood(
                station,
                result,
                canUpdateLastKnownGood: canCommit,
              );
              if (canCommit) {
                _waterUiCache[key] = _WaterUiCacheEntry(
                  result: resolved,
                  savedAt: DateTime.now(),
                );
                if (_hasValidReading(resolved)) {
                  unawaited(_persistHomeSnapshot(station, resolved));
                }
              }
              return _withCurrentFreshness(resolved, DateTime.now());
            })
            .whenComplete(() {
              if (identical(_waterUiInFlight[key], request)) {
                _waterUiInFlight.remove(key);
              }
            });
    _waterUiInFlight[key] = request;
    return request;
  }

  Stream<WaterUiResult> getProgressiveWaterUiResults(
    Station station, {
    int limit = 72,
    Duration historyWindow = const Duration(hours: 24),
    bool forceRefresh = false,
  }) async* {
    final now = DateTime.now();
    // Snapshot cache state before a forced refresh invalidates its entry. This
    // lets the UI keep the last real reading visible while the provider call
    // runs in the background.
    final cached = _cachedWaterUiResult(
      station,
      limit: limit,
      historyWindow: historyWindow,
      now: now,
    );
    final lastKnownGood = cached == null
        ? _lastKnownGoodResult(station, now)
        : null;
    final canonicalFuture = getWaterUiResult(
      station,
      limit: limit,
      historyWindow: historyWindow,
      forceRefresh: forceRefresh,
    );
    WaterUiResult? displayed;

    if (cached != null && _hasValidReading(cached)) {
      displayed = cached;
      yield cached;
    } else if (lastKnownGood != null) {
      displayed = lastKnownGood;
      yield lastKnownGood;
    }

    final fastResult = _fastResultFromStation(station, now);
    if (fastResult != null &&
        (displayed == null ||
            _shouldReplaceDisplayed(displayed, fastResult, now))) {
      displayed = fastResult;
      yield fastResult;
    }

    final canonical = await canonicalFuture;
    if (displayed == null ||
        forceRefresh ||
        _shouldReplaceDisplayed(displayed, canonical, DateTime.now())) {
      yield canonical;
    }
  }

  /// Returns only a cached or last-known-good result for [station]. It never
  /// starts a provider request, so callers can render a station-consistent
  /// value immediately while scheduling a background refresh.
  WaterUiResult? cachedWaterUiResult(
    Station station, {
    int limit = 72,
    Duration historyWindow = const Duration(hours: 24),
  }) {
    final now = DateTime.now();
    return _cachedWaterUiResult(
          station,
          limit: limit,
          historyWindow: historyWindow,
          now: now,
        ) ??
        _lastKnownGoodResult(station, now);
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
        prefetchedCurrentReading:
            stationReading?.source == WaterLevelSource.danubeFis
            ? stationReading
            : null,
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

    final validReadings =
        repositoryResult.readings
            .where(_isValidReading)
            .where((reading) => !reading.timestamp.isAfter(now))
            .toList(growable: false)
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final selectedReading = _latestReadingByAuthority(
      stationReading,
      validReadings,
      now,
    );
    final compatibleReadings = selectedReading == null
        ? const <WaterLevel>[]
        : _historyThroughSelectedReading(validReadings, selectedReading);
    final history = _withCompatibleTrends(compatibleReadings);
    final latestReading = selectedReading == null
        ? null
        : _withCompatibleTrend(selectedReading, compatibleReadings);
    final previousReading = latestReading == null
        ? null
        : _previousCompatibleReading(latestReading, history);
    final deltaCm = latestReading == null || previousReading == null
        ? null
        : latestReading.value - previousReading.value;
    final comparisonDuration = latestReading == null || previousReading == null
        ? null
        : latestReading.timestamp.difference(previousReading.timestamp);
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
      previousReading: previousReading,
      deltaCm: deltaCm,
      comparisonDuration: comparisonDuration,
      trend: latestReading?.hasKnownTrend == true ? latestReading?.trend : null,
      hasEnoughHistory: previousReading != null,
      providerError: repositoryResult.hadProviderError,
    );
  }

  static WaterLevel? _previousCompatibleReading(
    WaterLevel latest,
    List<WaterLevel> history,
  ) {
    for (final candidate in history.reversed) {
      if (_sourcesCanShareHistory(candidate.source, latest.source) &&
          candidate.unit.toLowerCase() == 'cm' &&
          candidate.timestamp.isBefore(latest.timestamp)) {
        return candidate;
      }
    }
    return null;
  }

  static List<WaterLevel> _historyThroughSelectedReading(
    List<WaterLevel> readings,
    WaterLevel selectedReading,
  ) {
    final selectedTimestamp = selectedReading.timestamp.toUtc();
    final byTimestamp = <int, WaterLevel>{};
    for (final reading in readings) {
      if (!_sourcesCanShareHistory(reading.source, selectedReading.source) ||
          reading.timestamp.toUtc().isAfter(selectedTimestamp)) {
        continue;
      }
      byTimestamp[reading.timestamp.toUtc().microsecondsSinceEpoch] = reading;
    }
    // The authoritative current observation can come from the prefetched
    // station feed rather than the history provider. It is still a real
    // observation and must close the chart series instead of being shown only
    // in the hero summary.
    byTimestamp[selectedTimestamp.microsecondsSinceEpoch] = selectedReading;
    final chronological = byTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return chronological;
  }

  Future<List<Station>> getStations({bool forceRefresh = false}) async =>
      (await getStationsResult(forceRefresh: forceRefresh)).value;

  Future<WaterStationBatchResult> getStationBatchResult({
    bool forceRefresh = false,
    int limit = 72,
    Duration historyWindow = const Duration(hours: 24),
  }) async {
    late final CacheResult<List<Station>> stationResult;
    try {
      stationResult = await _loadStationsResult(forceRefresh: forceRefresh);
    } on Exception catch (error) {
      return WaterStationBatchResult(
        stations: const <Station>[],
        resultsByStationId: const <String, WaterUiResult>{},
        totalStationCount: 0,
        stationWithReadingCount: 0,
        stationWithoutDataCount: 0,
        providerErrorCount: 0,
        latestMeasurementTimestamp: null,
        isStationListStaleFallback: false,
        stationListLoadFailed: true,
        safeDiagnosticMessage:
            'Water station list failed (${error.runtimeType})',
      );
    }

    final stations = stationResult.value;
    final orderedResults = List<WaterUiResult?>.filled(stations.length, null);
    var nextIndex = 0;

    Future<void> loadNext() async {
      while (true) {
        final index = nextIndex;
        if (index >= stations.length) return;
        nextIndex++;
        final station = stations[index];
        try {
          orderedResults[index] = await getWaterUiResult(
            station,
            limit: limit,
            historyWindow: historyWindow,
            forceRefresh: forceRefresh,
          );
        } on Exception catch (error) {
          orderedResults[index] = _withCurrentFreshness(
            _resolveWithLastKnownGood(
              station,
              _providerErrorResult(error),
              canUpdateLastKnownGood: false,
            ),
            DateTime.now(),
          );
        }
      }
    }

    final workerCount = stations.length < _maxBatchConcurrency
        ? stations.length
        : _maxBatchConcurrency;
    await Future.wait(List.generate(workerCount, (_) => loadNext()));

    final resultsByStationId = <String, WaterUiResult>{};
    var stationWithReadingCount = 0;
    var providerErrorCount = 0;
    DateTime? latestMeasurementTimestamp;
    for (var index = 0; index < stations.length; index++) {
      final result = orderedResults[index]!;
      resultsByStationId[stations[index].id] = result;
      final reading = result.latestReading;
      if (reading != null && _isValidReading(reading)) {
        stationWithReadingCount++;
        final timestamp = result.measurementTimestamp;
        if (timestamp != null &&
            timestamp.millisecondsSinceEpoch > 0 &&
            (latestMeasurementTimestamp == null ||
                timestamp.isAfter(latestMeasurementTimestamp))) {
          latestMeasurementTimestamp = timestamp;
        }
      }
      if (result.status == WaterUiStatus.providerError) {
        providerErrorCount++;
      }
    }

    return WaterStationBatchResult(
      stations: List<Station>.unmodifiable(stations),
      resultsByStationId: Map<String, WaterUiResult>.unmodifiable(
        resultsByStationId,
      ),
      totalStationCount: stations.length,
      stationWithReadingCount: stationWithReadingCount,
      stationWithoutDataCount: stations.length - stationWithReadingCount,
      providerErrorCount: providerErrorCount,
      latestMeasurementTimestamp: latestMeasurementTimestamp,
      isStationListStaleFallback: stationResult.isStaleFallback,
      stationListLoadFailed: false,
      safeDiagnosticMessage: null,
    );
  }

  Stream<WaterStationBatchResult> getProgressiveStationBatch({
    bool forceRefresh = false,
    int limit = 72,
    Duration historyWindow = const Duration(hours: 24),
  }) {
    late final StreamController<WaterStationBatchResult> controller;
    var isCanceled = false;
    controller = StreamController<WaterStationBatchResult>(
      onListen: () {
        final generation = ++_progressiveBatchGeneration;
        unawaited(
          _loadProgressiveStationBatch(
            controller: controller,
            generation: generation,
            isCanceled: () => isCanceled,
            forceRefresh: forceRefresh,
            limit: limit,
            historyWindow: historyWindow,
          ),
        );
      },
      onCancel: () => isCanceled = true,
    );
    return controller.stream;
  }

  Future<void> _loadProgressiveStationBatch({
    required StreamController<WaterStationBatchResult> controller,
    required int generation,
    required bool Function() isCanceled,
    required bool forceRefresh,
    required int limit,
    required Duration historyWindow,
  }) async {
    bool isActive() =>
        !isCanceled() && generation == _progressiveBatchGeneration;

    void emit(WaterStationBatchResult snapshot) {
      if (isActive() && !controller.isClosed) controller.add(snapshot);
    }

    try {
      late final CacheResult<List<Station>> stationResult;
      try {
        stationResult = await _loadStationsResult(forceRefresh: forceRefresh);
      } on Exception catch (error) {
        emit(
          WaterStationBatchResult(
            stations: const <Station>[],
            resultsByStationId: const <String, WaterUiResult>{},
            totalStationCount: 0,
            stationWithReadingCount: 0,
            stationWithoutDataCount: 0,
            providerErrorCount: 0,
            latestMeasurementTimestamp: null,
            isStationListStaleFallback: false,
            stationListLoadFailed: true,
            safeDiagnosticMessage:
                'Water station list failed (${error.runtimeType})',
            isComplete: true,
          ),
        );
        return;
      }

      if (!isActive()) return;
      final stations = List<Station>.unmodifiable(stationResult.value);
      final resultsByStationId = <String, WaterUiResult>{};
      emit(
        _buildProgressiveSnapshot(
          stations: stations,
          resultsByStationId: resultsByStationId,
          isStationListStaleFallback: stationResult.isStaleFallback,
          isComplete: stations.isEmpty,
        ),
      );
      if (stations.isEmpty) return;

      final now = DateTime.now();
      for (final station in stations) {
        final lastKnownGood = _lastKnownGoodResult(station, now);
        if (lastKnownGood != null) {
          resultsByStationId[station.id] = lastKnownGood;
        }
      }
      if (resultsByStationId.isNotEmpty) {
        emit(
          _buildProgressiveSnapshot(
            stations: stations,
            resultsByStationId: resultsByStationId,
            isStationListStaleFallback: stationResult.isStaleFallback,
            isComplete: false,
          ),
        );
      }

      final completedStationIds = <String>{};
      if (!forceRefresh) {
        for (final station in stations) {
          final cached = _cachedWaterUiResult(
            station,
            limit: limit,
            historyWindow: historyWindow,
            now: now,
          );
          if (cached != null) {
            resultsByStationId[station.id] = cached;
            completedStationIds.add(station.id);
          }
        }
        if (completedStationIds.isNotEmpty) {
          emit(
            _buildProgressiveSnapshot(
              stations: stations,
              resultsByStationId: resultsByStationId,
              isStationListStaleFallback: stationResult.isStaleFallback,
              isComplete: completedStationIds.length == stations.length,
            ),
          );
        }
      }

      final pendingStations = stations
          .where((station) => !completedStationIds.contains(station.id))
          .toList(growable: false);
      if (pendingStations.isEmpty) return;

      var nextIndex = 0;
      Future<void> loadNext() async {
        while (isActive()) {
          final index = nextIndex;
          if (index >= pendingStations.length) return;
          nextIndex++;
          final station = pendingStations[index];
          late final WaterUiResult result;
          try {
            result = await getWaterUiResult(
              station,
              limit: limit,
              historyWindow: historyWindow,
              forceRefresh: forceRefresh,
            );
          } on Exception catch (error) {
            result = _withCurrentFreshness(
              _resolveWithLastKnownGood(
                station,
                _providerErrorResult(error),
                canUpdateLastKnownGood: false,
              ),
              DateTime.now(),
            );
          }
          if (!isActive()) return;
          resultsByStationId[station.id] = result;
          completedStationIds.add(station.id);
          emit(
            _buildProgressiveSnapshot(
              stations: stations,
              resultsByStationId: resultsByStationId,
              isStationListStaleFallback: stationResult.isStaleFallback,
              isComplete: completedStationIds.length == stations.length,
            ),
          );
        }
      }

      final workerCount = pendingStations.length < _maxBatchConcurrency
          ? pendingStations.length
          : _maxBatchConcurrency;
      await Future.wait(List.generate(workerCount, (_) => loadNext()));
    } finally {
      if (!controller.isClosed) await controller.close();
    }
  }

  WaterUiResult? _cachedWaterUiResult(
    Station station, {
    required int limit,
    required Duration historyWindow,
    required DateTime now,
  }) {
    final key = _waterUiCacheKey(station, limit, historyWindow);
    final cached = _waterUiCache[key];
    if (cached == null || now.difference(cached.savedAt) >= cacheDuration) {
      return null;
    }
    final resolved = _resolveWithLastKnownGood(
      station,
      cached.result,
      canUpdateLastKnownGood: true,
    );
    return _withCurrentFreshness(resolved, now);
  }

  static WaterUiResult _providerErrorResult(Object error) => WaterUiResult(
    latestReading: null,
    history: const <WaterLevel>[],
    source: null,
    sourceName: null,
    measurementTimestamp: null,
    dataAge: null,
    isStale: false,
    status: WaterUiStatus.providerError,
    safeDiagnosticMessage:
        'Water station request failed (${error.runtimeType})',
  );

  static WaterStationBatchResult _buildProgressiveSnapshot({
    required List<Station> stations,
    required Map<String, WaterUiResult> resultsByStationId,
    required bool isStationListStaleFallback,
    required bool isComplete,
  }) {
    final orderedResults = <String, WaterUiResult>{};
    var stationWithReadingCount = 0;
    var stationWithoutDataCount = 0;
    var providerErrorCount = 0;
    DateTime? latestMeasurementTimestamp;
    for (final station in stations) {
      final result = resultsByStationId[station.id];
      if (result == null) continue;
      orderedResults[station.id] = result;
      final reading = result.latestReading;
      if (reading != null && _isValidReading(reading)) {
        stationWithReadingCount++;
        final timestamp = result.measurementTimestamp;
        if (timestamp != null &&
            timestamp.millisecondsSinceEpoch > 0 &&
            (latestMeasurementTimestamp == null ||
                timestamp.isAfter(latestMeasurementTimestamp))) {
          latestMeasurementTimestamp = timestamp;
        }
      } else {
        stationWithoutDataCount++;
      }
      if (result.status == WaterUiStatus.providerError) {
        providerErrorCount++;
      }
    }

    return WaterStationBatchResult(
      stations: stations,
      resultsByStationId: Map<String, WaterUiResult>.unmodifiable(
        orderedResults,
      ),
      totalStationCount: stations.length,
      stationWithReadingCount: stationWithReadingCount,
      stationWithoutDataCount: stationWithoutDataCount,
      providerErrorCount: providerErrorCount,
      latestMeasurementTimestamp: latestMeasurementTimestamp,
      isStationListStaleFallback: isStationListStaleFallback,
      stationListLoadFailed: false,
      safeDiagnosticMessage: null,
      isComplete: isComplete,
    );
  }

  Future<CacheResult<List<Station>>> getStationsResult({
    bool forceRefresh = false,
  }) async {
    try {
      return await _loadStationsResult(forceRefresh: forceRefresh);
    } on Exception {
      return const CacheResult<List<Station>>(<Station>[]);
    }
  }

  Future<CacheResult<List<Station>>> _loadStationsResult({
    required bool forceRefresh,
  }) {
    return _stationsCache.get(
      () async => List<Station>.unmodifiable(await _repository.getStations()),
      forceRefresh: forceRefresh,
    );
  }

  Future<Station?> getNearestStation({Station? fallbackStation}) async {
    List<Station> stations;
    try {
      stations = (await _fastStationsCache.get(
        () async =>
            List<Station>.unmodifiable(await _repository.getFastStations()),
      )).value;
    } on Exception {
      stations = await getStations();
    }
    if (stations.isEmpty) {
      return null;
    }

    final selected = fallbackStation ?? _selectedStation;
    if (selected != null) {
      for (final station in stations) {
        if (station.id == selected.id) return station;
      }
      return selected;
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
      return stations.first;
    }
  }

  String _waterUiCacheKey(Station station, int limit, Duration historyWindow) {
    final measurementTimestamp = station.hasWaterLevel
        ? station.lastUpdate.microsecondsSinceEpoch
        : 'none';
    return '${identityHashCode(_repository)}:${station.id}:'
        '$measurementTimestamp:$limit:${historyWindow.inMicroseconds}';
  }

  String _lastKnownGoodKey(Station station) =>
      '${identityHashCode(_repository)}:${station.id}';

  WaterUiResult? _lastKnownGoodResult(Station station, DateTime now) {
    final result = _lastKnownGoodByStation[_lastKnownGoodKey(station)];
    if (result == null || !_hasValidReading(result)) return null;
    return _withCurrentFreshness(result, now);
  }

  WaterUiResult _resolveWithLastKnownGood(
    Station station,
    WaterUiResult result, {
    required bool canUpdateLastKnownGood,
  }) {
    final key = _lastKnownGoodKey(station);
    final previous = _lastKnownGoodByStation[key];
    if (_hasValidReading(result)) {
      final previousTimestamp = previous?.measurementTimestamp;
      final resultTimestamp = result.measurementTimestamp!;
      if (previousTimestamp != null &&
          previousTimestamp.isAfter(resultTimestamp)) {
        return previous!;
      }
      if (canUpdateLastKnownGood) {
        _lastKnownGoodByStation[key] = result;
      }
      return result;
    }

    if (previous == null || !_hasValidReading(previous)) return result;
    return WaterUiResult(
      latestReading: previous.latestReading,
      history: previous.history,
      source: previous.source,
      sourceName: previous.sourceName,
      measurementTimestamp: previous.measurementTimestamp,
      dataAge: previous.dataAge,
      isStale: previous.isStale,
      status: WaterUiStatus.providerError,
      safeDiagnosticMessage:
          result.safeDiagnosticMessage ?? 'Water update temporarily failed',
      previousReading: previous.previousReading,
      deltaCm: previous.deltaCm,
      comparisonDuration: previous.comparisonDuration,
      trend: previous.trend,
      hasEnoughHistory: previous.hasEnoughHistory,
      providerError: true,
    );
  }

  static bool _hasValidReading(WaterUiResult result) {
    final reading = result.latestReading;
    return reading != null &&
        _isValidReading(reading) &&
        result.measurementTimestamp != null &&
        result.measurementTimestamp!.millisecondsSinceEpoch > 0;
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
      previousReading: result.previousReading,
      deltaCm: result.deltaCm,
      comparisonDuration: result.comparisonDuration,
      trend: result.trend,
      hasEnoughHistory: result.hasEnoughHistory,
      providerError: result.providerError,
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
    DateTime now,
  ) {
    final candidates = <WaterLevel>[
      if (stationReading != null && _isValidReading(stationReading))
        stationReading,
      ...history.where(_isValidReading),
    ];
    if (candidates.isEmpty) return null;

    final freshAfdj = candidates.where(
      (reading) =>
          reading.source == WaterLevelSource.afdj &&
          _isFreshReading(reading, now),
    );
    if (freshAfdj.isNotEmpty) {
      return freshAfdj.reduce(
        (current, candidate) =>
            candidate.timestamp.toUtc().isAfter(current.timestamp.toUtc())
            ? candidate
            : current,
      );
    }

    final official = candidates.where(
      (reading) => _isOfficialSource(reading.source),
    );
    final authoritativeCandidates = official.isEmpty ? candidates : official;
    return authoritativeCandidates.reduce(
      (current, candidate) =>
          candidate.timestamp.isAfter(current.timestamp) ? candidate : current,
    );
  }

  static WaterUiResult? _fastResultFromStation(Station station, DateTime now) {
    final reading = _readingFromStation(station);
    if (reading == null ||
        !_isOfficialSource(reading.source) ||
        reading.unit.toLowerCase() != 'cm' ||
        !_isValidReading(reading)) {
      return null;
    }
    final current = reading.hasKnownTrend
        ? reading
        : _copyWithTrend(reading, null);
    return _withCurrentFreshness(
      WaterUiResult(
        latestReading: current,
        history: const <WaterLevel>[],
        source: current.source,
        sourceName: current.sourceName,
        measurementTimestamp: current.timestamp,
        dataAge: null,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        safeDiagnosticMessage: null,
      ),
      now,
    );
  }

  static bool _shouldReplaceDisplayed(
    WaterUiResult current,
    WaterUiResult candidate,
    DateTime now,
  ) {
    if (!_hasValidReading(candidate)) return false;
    if (!_hasValidReading(current)) return true;
    final currentReading = current.latestReading!;
    final candidateReading = candidate.latestReading!;
    final currentAfdj =
        currentReading.source == WaterLevelSource.afdj &&
        _isFreshReading(currentReading, now);
    final candidateAfdj =
        candidateReading.source == WaterLevelSource.afdj &&
        _isFreshReading(candidateReading, now);
    if (candidateAfdj != currentAfdj) return candidateAfdj;

    final currentTimestamp = currentReading.timestamp.toUtc();
    final candidateTimestamp = candidateReading.timestamp.toUtc();
    if (candidateTimestamp.isAfter(currentTimestamp)) return true;
    if (candidateTimestamp.isBefore(currentTimestamp)) return false;

    return candidate.status != current.status ||
        candidate.isStale != current.isStale ||
        candidate.source != current.source ||
        candidate.sourceName != current.sourceName ||
        candidateReading.value != currentReading.value ||
        candidateReading.unit != currentReading.unit ||
        candidateReading.trend != currentReading.trend ||
        candidateReading.hasKnownTrend != currentReading.hasKnownTrend ||
        candidate.history.length != current.history.length ||
        candidate.safeDiagnosticMessage != current.safeDiagnosticMessage;
  }

  static bool _isFreshReading(WaterLevel reading, DateTime now) {
    final age = now.toUtc().difference(reading.timestamp.toUtc());
    return age >= const Duration(minutes: -5) &&
        age <= WaterRepository.defaultFreshnessThreshold;
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
    if (previous == null ||
        !_sourcesCanShareHistory(previous.source, reading.source)) {
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

  static bool _sourcesCanShareHistory(
    WaterLevelSource first,
    WaterLevelSource second,
  ) =>
      first == second ||
      (first != WaterLevelSource.manualFallback &&
          second != WaterLevelSource.manualFallback);

  static bool _isOfficialSource(WaterLevelSource source) => switch (source) {
    WaterLevelSource.afdj ||
    WaterLevelSource.danubeHis ||
    WaterLevelSource.danubeFis ||
    WaterLevelSource.inhga => true,
    WaterLevelSource.manualFallback => false,
  };

  static bool _isValidReading(WaterLevel reading) {
    final timestamp = reading.timestamp.toUtc();
    return reading.value.isFinite &&
        timestamp.millisecondsSinceEpoch > 0 &&
        !timestamp.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );
  }

  static Duration _nonNegativeAge(DateTime now, DateTime timestamp) {
    final age = now.toUtc().difference(timestamp.toUtc());
    return age.isNegative ? Duration.zero : age;
  }
}
