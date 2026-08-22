import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/station.dart';
import '../core/cache/timed_cache.dart';
import '../core/water/water_history_analysis.dart';
import '../models/water_level.dart';
import '../repositories/water_repository.dart';
import 'location_service.dart';
import 'diagnostics_service.dart';

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
    this.freshnessTimestamp,
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
  final DateTime? freshnessTimestamp;
  final Duration? dataAge;
  final bool isStale;
  final List<WaterLevel> history;
  final WaterStationDetailsRange selectedRange;
  final WaterStationDetailsHistoryStatus historyStatus;
  final double? dailyDeltaCm;
  final WaterTrend? trend;
  final String? safeDiagnosticMessage;

  DateTime? get effectiveFreshnessTimestamp =>
      freshnessTimestamp ??
      currentReading?.effectiveFreshnessTimestamp ??
      measurementTimestamp;
}

class WaterUiResult {
  const WaterUiResult({
    required this.latestReading,
    required this.history,
    required this.source,
    required this.sourceName,
    required this.measurementTimestamp,
    this.freshnessTimestamp,
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
    this.canonicalTrend,
  });

  final WaterLevel? latestReading;
  final List<WaterLevel> history;
  final WaterLevelSource? source;
  final String? sourceName;
  final DateTime? measurementTimestamp;
  final DateTime? freshnessTimestamp;
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
  final WaterTrendResult? canonicalTrend;

  DateTime? get effectiveFreshnessTimestamp =>
      freshnessTimestamp ??
      latestReading?.effectiveFreshnessTimestamp ??
      measurementTimestamp;

  WaterTrendResult? get effectiveCanonicalTrend =>
      canonicalTrend ??
      canonicalWaterTrendResult(
        history,
        currentObservation: latestReading,
        stationId: latestReading?.stationId,
      );
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
  static const homeNearbyStationRadiusKm = 100.0;
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
  static String? _restoredPinnedStationId;
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
    _restoredPinnedStationId = station.id;
    _selectionMode = WaterStationSelectionMode.pinned;
    _selectionWasExplicitlySet = true;
    unawaited(_persistPinnedStation(station.id));
    _stationSelectionController.add(station);
  }

  Future<void> setAutomatic() async {
    _selectedStation = null;
    _restoredPinnedStationId = null;
    _selectionMode = WaterStationSelectionMode.automatic;
    _selectionWasExplicitlySet = true;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectionModeKey, 'automatic');
    await preferences.remove(_pinnedStationIdKey);
  }

  Future<void> clearSelection() => setAutomatic();

  Future<WaterHomeStationSelection> resolveHomeStationSelection({
    double? currentLatitude,
    double? currentLongitude,
  }) async {
    await _restoreSelection();
    final stations = await getStations();
    final canonicalStations = orderCanonicalStations(stations);

    if (_selectionMode == WaterStationSelectionMode.pinned) {
      final pinnedId = _selectedStation?.id ?? _restoredPinnedStationId;
      final restored = pinnedId == null
          ? null
          : canonicalStations
                .where((station) => station.id == pinnedId)
                .firstOrNull;
      if (restored != null) {
        _selectedStation = restored;
        _restoredPinnedStationId = restored.id;
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
      if (currentLatitude == null || currentLongitude == null) {
        final position = await _locationService.determinePosition();
        currentLatitude = position.latitude;
        currentLongitude = position.longitude;
      }
      final latitude = currentLatitude;
      final longitude = currentLongitude;
      final candidates = rankHomeCandidates(
        stations,
        latitude: latitude,
        longitude: longitude,
      );
      final automaticStations = rankCanonicalStations(
        canonicalStations,
        latitude: latitude,
        longitude: longitude,
      );
      final nearest = automaticStations.firstOrNull;
      final automaticStation =
          nearest != null &&
              isStationWithinHomeRadius(
                nearest,
                latitude: latitude,
                longitude: longitude,
              )
          ? nearest
          : null;
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

    _lastAutomaticStation = null;
    return WaterHomeStationSelection(
      mode: WaterStationSelectionMode.automatic,
      station: null,
      candidates: rankHomeCandidates(stations),
      canonicalStations: canonicalStations,
    );
  }

  /// Resolves Water only from the supplied context coordinates. Persisted
  /// Water preferences are deliberately ignored so they cannot leak into an
  /// unrelated Ask Fluvi or FluviScore context.
  Future<Station?> resolveNearestStationForContext({
    required double latitude,
    required double longitude,
  }) async {
    final stations = orderCanonicalStations(await getStations());
    final nearest = rankCanonicalStations(
      stations,
      latitude: latitude,
      longitude: longitude,
    ).firstOrNull;
    if (nearest == null ||
        !isStationWithinHomeRadius(
          nearest,
          latitude: latitude,
          longitude: longitude,
        )) {
      return null;
    }
    return nearest;
  }

  /// Resolves an explicit station identity without falling back to a
  /// different station, a persisted preference, or catalog order.
  Future<Station?> stationForContextId(String stationId) async {
    final normalized = stationId.trim();
    if (normalized.isEmpty) return null;
    return (await getStations())
        .where((station) => station.id == normalized)
        .firstOrNull;
  }

  static bool isStationWithinHomeRadius(
    Station station, {
    required double latitude,
    required double longitude,
  }) =>
      Geolocator.distanceBetween(
        latitude,
        longitude,
        station.latitude,
        station.longitude,
      ) <=
      homeNearbyStationRadiusKm * 1000;

  /// Legacy display order retained only for the direct-provider fallback.
  /// Production selection is driven by the backend catalog and stable IDs.
  static List<String> get canonicalStationNames =>
      WaterRepository.officialAfdjStationOrder;

  static List<Station> orderCanonicalStations(Iterable<Station> stations) {
    final seenIds = <String>{};
    return List<Station>.unmodifiable(
      stations.where((station) {
        final id = station.id.trim();
        return id.isNotEmpty && seenIds.add(id);
      }),
    );
  }

  static List<Station> filterStations(
    Iterable<Station> stations,
    String query,
  ) {
    final normalizedQuery = _normalizeStationName(query);
    final ordered = orderCanonicalStations(stations);
    if (normalizedQuery.isEmpty) return ordered;

    return List<Station>.unmodifiable(
      ordered.where((station) {
        return _normalizeStationName(station.name).contains(normalizedQuery) ||
            _normalizeStationName(station.river).contains(normalizedQuery) ||
            _normalizeStationName(station.id).contains(normalizedQuery);
      }),
    );
  }

  /// Compatibility helper for older callers and tests. Product selection does
  /// not depend on names; IDs remain the source of truth.
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
    final ordered = orderCanonicalStations(stations);
    final sourceOrder = <String, int>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: index,
    };
    final ranked = ordered
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
      return (sourceOrder[left.id] ?? 0x3fffffff).compareTo(
        sourceOrder[right.id] ?? 0x3fffffff,
      );
    });
    return List<Station>.unmodifiable(ranked);
  }

  static List<Station> eligibleHomeStations(Iterable<Station> stations) {
    final seenIds = <String>{};
    return stations
        .where(
          (station) =>
              station.id.trim().isNotEmpty &&
              seenIds.add(station.id) &&
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
    final ordered = eligibleHomeStations(stations);
    final sourceOrder = <String, int>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: index,
    };
    final candidates = ordered.toList();
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
      final bySourceOrder = (sourceOrder[left.id] ?? 0x3fffffff).compareTo(
        sourceOrder[right.id] ?? 0x3fffffff,
      );
      if (bySourceOrder != 0) return bySourceOrder;
      return left.id.compareTo(right.id);
    });
    return List<Station>.unmodifiable(candidates.take(5));
  }

  static void resetStationSelectionForTest() {
    _selectedStation = null;
    _restoredPinnedStationId = null;
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
        _selectedStation = null;
        _restoredPinnedStationId = pinnedId;
      } else {
        _selectionMode = WaterStationSelectionMode.automatic;
        _selectedStation = null;
        _restoredPinnedStationId = null;
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
          (_selectedStation?.id ?? _restoredPinnedStationId) == station.id) {
        _selectedStation = station;
        _restoredPinnedStationId = station.id;
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
        'freshness_timestamp': latest.effectiveFreshnessTimestamp
            .toUtc()
            .toIso8601String(),
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
      return (_selectedStation?.id ?? _restoredPinnedStationId) == station.id;
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
        '${latest.reportedDeltaCm24h}:${latest.waterTemperatureC}:'
        '${latest.forecast.length}:'
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
      'country_code': station.countryCode,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'level': latest.value,
      'trend': latest.trend.name,
      'last_update': latest.timestamp.toUtc().toIso8601String(),
      'water_freshness_timestamp': latest.effectiveFreshnessTimestamp
          .toUtc()
          .toIso8601String(),
      'water_type': station.waterBodyType.name,
      'species': station.species,
      'difficulty': station.difficulty.name,
      'is_favorite': station.isFavorite,
      'has_water_level': true,
      'has_known_trend': latest.hasKnownTrend,
      'water_level_unit': latest.unit,
      'water_level_source': latest.source.name,
      'water_measurement_precision': latest.measurementPrecision.name,
      'reported_delta_cm_24h': latest.reportedDeltaCm24h,
      'water_temperature_c': latest.waterTemperatureC,
    };
  }

  static Map<String, Object?> _waterLevelToPersistedMap(WaterLevel reading) {
    return <String, Object?>{
      'station_id': reading.stationId,
      'value': reading.value,
      'timestamp': reading.timestamp.toUtc().toIso8601String(),
      'freshness_timestamp': reading.freshnessTimestamp
          ?.toUtc()
          .toIso8601String(),
      'measurement_precision': reading.measurementPrecision.name,
      'trend': reading.trend.name,
      'source': reading.source.name,
      'unit': reading.unit,
      'source_name': reading.sourceName,
      'has_known_trend': reading.hasKnownTrend,
      'metric_code': reading.metricCode,
      'measurement_datum': reading.measurementDatum,
      'history_contract': reading.historyContract,
      'is_quality_valid': reading.isQualityValid,
      'measurement_resolution': reading.measurementResolution,
      'reported_delta_cm_24h': reading.reportedDeltaCm24h,
      'water_temperature_c': reading.waterTemperatureC,
      'forecast': reading.forecast
          .map((point) => point.toJson())
          .toList(growable: false),
      'forecast_updated_at': reading.forecastUpdatedAt
          ?.toUtc()
          .toIso8601String(),
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
    final freshnessTimestamp = DateTime.tryParse(
      map['freshness_timestamp']?.toString() ?? '',
    );
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
      freshnessTimestamp: freshnessTimestamp,
      measurementPrecision: WaterMeasurementPrecision.parse(
        map['measurement_precision'],
      ),
      trend: parsedTrend ?? WaterTrend.stable,
      source: source,
      unit: unit,
      sourceName: sourceName == null || sourceName.isEmpty
          ? _canonicalSourceName(source)
          : sourceName,
      hasKnownTrend: hasKnownTrend,
      metricCode: map['metric_code']?.toString() ?? 'water_level',
      measurementDatum: map['measurement_datum']?.toString() ?? 'source_native',
      historyContract:
          map['history_contract']?.toString() ?? 'canonical_water_level',
      isQualityValid: map['is_quality_valid'] != false,
      measurementResolution: map['measurement_resolution'] is num
          ? (map['measurement_resolution'] as num).toDouble()
          : double.tryParse(map['measurement_resolution']?.toString() ?? ''),
      reportedDeltaCm24h: map['reported_delta_cm_24h'] is num
          ? (map['reported_delta_cm_24h'] as num).toDouble()
          : double.tryParse(map['reported_delta_cm_24h']?.toString() ?? ''),
      waterTemperatureC: map['water_temperature_c'] is num
          ? (map['water_temperature_c'] as num).toDouble()
          : double.tryParse(map['water_temperature_c']?.toString() ?? ''),
      forecast: WaterForecastPoint.listFromJson(map['forecast']),
      forecastUpdatedAt: DateTime.tryParse(
        map['forecast_updated_at']?.toString() ?? '',
      ),
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
      .replaceAll('ţ', 't')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

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
        freshnessTimestamp: currentResult.effectiveFreshnessTimestamp,
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
      freshnessTimestamp: currentResult.effectiveFreshnessTimestamp,
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
    if (activeRequest != null) {
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.water,
        operation: 'water_ui_deduped',
        message: 'Reused in-flight Water request',
        metadata: <String, Object?>{'station_id': station.id},
      );
      return activeRequest;
    }

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
        final fresh = _withCurrentFreshness(resolved, now);
        DiagnosticsService.instance.record(
          category: DiagnosticCategory.cache,
          operation: 'water_cache_hit',
          message: fresh.status.name,
          metadata: <String, Object?>{
            'station_id': station.id,
            'source': fresh.sourceName,
            'history_points': fresh.history.length,
          },
        );
        return Future<WaterUiResult>.value(fresh);
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
              final fresh = _withCurrentFreshness(resolved, DateTime.now());
              DiagnosticsService.instance.record(
                category: DiagnosticCategory.water,
                operation: 'water_ui_result',
                message: fresh.status.name,
                metadata: <String, Object?>{
                  'station_id': station.id,
                  'source': fresh.sourceName,
                  'level_cm': fresh.latestReading?.value,
                  'history_points': fresh.history.length,
                  'stale': fresh.isStale,
                  'provider_error': fresh.providerError,
                },
              );
              return fresh;
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
    final canonicalTrend = canonicalWaterTrendResult(
      compatibleReadings,
      currentObservation: selectedReading,
      stationId: station.id,
    );
    final history =
        canonicalTrend?.history.realObservations ?? const <WaterLevel>[];
    final reportedDeltaCm24h = selectedReading?.reportedDeltaCm24h;
    final hasReportedDelta =
        reportedDeltaCm24h != null && reportedDeltaCm24h.isFinite;
    final reportedTrend = hasReportedDelta
        ? waterTrendFromRealDelta(
            reportedDeltaCm24h,
            measurementResolution: selectedReading?.measurementResolution,
          )
        : null;
    final displayTrend = reportedTrend ?? canonicalTrend?.trend.displayTrend;
    final latestReading = selectedReading == null
        ? null
        : _copyWithResolvedTrend(selectedReading, displayTrend);
    final previousReading = canonicalTrend?.delta?.referenceObservation;
    final deltaCm = hasReportedDelta
        ? reportedDeltaCm24h
        : canonicalTrend?.delta?.value;
    final comparisonDuration = hasReportedDelta
        ? const Duration(hours: 24)
        : canonicalTrend?.delta?.actualInterval;
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
      trend: displayTrend,
      hasEnoughHistory: previousReading != null,
      providerError: repositoryResult.hadProviderError,
      canonicalTrend: canonicalTrend,
    );
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
      final nearest = stations.reduce((nearest, candidate) {
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
      return isStationWithinHomeRadius(
            nearest,
            latitude: position.latitude,
            longitude: position.longitude,
          )
          ? nearest
          : null;
    } on LocationFailure {
      return null;
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
      canonicalTrend: previous.effectiveCanonicalTrend,
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
    final freshnessTimestamp = result.effectiveFreshnessTimestamp;
    final dataAge = freshnessTimestamp == null
        ? null
        : _nonNegativeAge(now, freshnessTimestamp);
    final isStale =
        dataAge != null && dataAge > WaterRepository.defaultFreshnessThreshold;
    return WaterUiResult(
      latestReading: result.latestReading,
      history: result.history,
      source: result.source,
      sourceName: result.sourceName,
      measurementTimestamp: timestamp,
      freshnessTimestamp: freshnessTimestamp,
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
      canonicalTrend: result.effectiveCanonicalTrend,
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
      freshnessTimestamp: station.waterFreshnessTimestamp,
      measurementPrecision: WaterMeasurementPrecision.parse(
        station.waterMeasurementPrecision,
      ),
      trend: station.trend,
      source: WaterLevelSource.parse(station.waterLevelSource),
      unit: station.waterLevelUnit,
      sourceName: station.waterLevelSource,
      hasKnownTrend: station.hasKnownTrend,
      reportedDeltaCm24h: station.reportedDeltaCm24h,
      waterTemperatureC: station.waterTemperatureC,
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

    final official = candidates
        .where((reading) => _isOfficialSource(reading.source))
        .toList(growable: false);
    final authoritativeCandidates = official.isEmpty ? candidates : official;
    final fresh = authoritativeCandidates
        .where((reading) => _isFreshReading(reading, now))
        .toList(growable: false);
    final freshAfdj = fresh
        .where((reading) => reading.source == WaterLevelSource.afdj)
        .toList(growable: false);
    final preferred = freshAfdj.isNotEmpty
        ? freshAfdj
        : fresh.isNotEmpty
        ? fresh
        : authoritativeCandidates;
    return preferred.reduce((current, candidate) {
      final currentTimestamp = current.timestamp.toUtc();
      final candidateTimestamp = candidate.timestamp.toUtc();
      if (candidateTimestamp.isAfter(currentTimestamp)) return candidate;
      if (candidateTimestamp.isBefore(currentTimestamp)) return current;
      return _mergeEquivalentReadings(current, candidate);
    });
  }

  static WaterLevel _mergeEquivalentReadings(
    WaterLevel current,
    WaterLevel candidate,
  ) {
    if (current.stationId != candidate.stationId ||
        current.source != candidate.source ||
        current.unit != candidate.unit ||
        current.value != candidate.value) {
      return current;
    }

    final reportedDeltaCm24h =
        current.reportedDeltaCm24h ?? candidate.reportedDeltaCm24h;
    final reportedTrend = waterTrendFromRealDelta(
      reportedDeltaCm24h,
      measurementResolution:
          current.measurementResolution ?? candidate.measurementResolution,
    );
    final resolvedTrend =
        reportedTrend ?? current.knownTrend ?? candidate.knownTrend;
    final forecast = current.forecast.isNotEmpty
        ? current.forecast
        : candidate.forecast;
    final forecastUpdatedAt = current.forecastUpdatedAt == null
        ? candidate.forecastUpdatedAt
        : candidate.forecastUpdatedAt == null
        ? current.forecastUpdatedAt
        : current.forecastUpdatedAt!.isAfter(candidate.forecastUpdatedAt!)
        ? current.forecastUpdatedAt
        : candidate.forecastUpdatedAt;

    return WaterLevel(
      stationId: current.stationId,
      value: current.value,
      timestamp: current.timestamp,
      freshnessTimestamp:
          current.freshnessTimestamp ?? candidate.freshnessTimestamp,
      measurementPrecision:
          current.measurementPrecision == WaterMeasurementPrecision.unknown
          ? candidate.measurementPrecision
          : current.measurementPrecision,
      trend: resolvedTrend ?? WaterTrend.stable,
      source: current.source,
      unit: current.unit,
      sourceName: current.sourceName.trim().isNotEmpty
          ? current.sourceName
          : candidate.sourceName,
      hasKnownTrend: resolvedTrend != null,
      metricCode: current.metricCode,
      measurementDatum: current.measurementDatum,
      historyContract: current.historyContract,
      isQualityValid: current.isQualityValid && candidate.isQualityValid,
      measurementResolution:
          current.measurementResolution ?? candidate.measurementResolution,
      reportedDeltaCm24h: reportedDeltaCm24h,
      waterTemperatureC:
          current.waterTemperatureC ?? candidate.waterTemperatureC,
      forecast: forecast,
      forecastUpdatedAt: forecastUpdatedAt,
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
    // The fast station payload contains one real observation. Provider-published
    // Δ24h is still valid without reconstructing a previous point; chart history
    // remains unavailable until the canonical history request completes.
    final reportedDeltaCm24h = reading.reportedDeltaCm24h;
    final hasReportedDelta =
        reportedDeltaCm24h != null && reportedDeltaCm24h.isFinite;
    final reportedTrend = hasReportedDelta
        ? waterTrendFromRealDelta(
            reportedDeltaCm24h,
            measurementResolution: reading.measurementResolution,
          )
        : reading.knownTrend;
    final current = _copyWithResolvedTrend(reading, reportedTrend);
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
        deltaCm: hasReportedDelta ? reportedDeltaCm24h : null,
        comparisonDuration: hasReportedDelta ? const Duration(hours: 24) : null,
        trend: reportedTrend,
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
        candidateReading.reportedDeltaCm24h !=
            currentReading.reportedDeltaCm24h ||
        candidateReading.waterTemperatureC !=
            currentReading.waterTemperatureC ||
        candidateReading.forecast.length != currentReading.forecast.length ||
        candidate.history.length != current.history.length ||
        candidate.safeDiagnosticMessage != current.safeDiagnosticMessage;
  }

  static bool _isFreshReading(WaterLevel reading, DateTime now) {
    final age = now.toUtc().difference(
      reading.effectiveFreshnessTimestamp.toUtc(),
    );
    return age >= const Duration(minutes: -5) &&
        age <= WaterRepository.defaultFreshnessThreshold;
  }

  static WaterLevel _copyWithTrend(WaterLevel reading, WaterLevel? previous) {
    if (previous == null ||
        !_sourcesCanShareHistory(previous.source, reading.source)) {
      return WaterLevel(
        stationId: reading.stationId,
        value: reading.value,
        timestamp: reading.timestamp,
        freshnessTimestamp: reading.freshnessTimestamp,
        measurementPrecision: reading.measurementPrecision,
        trend: WaterTrend.stable,
        source: reading.source,
        unit: reading.unit,
        sourceName: reading.sourceName,
        hasKnownTrend: false,
        metricCode: reading.metricCode,
        measurementDatum: reading.measurementDatum,
        historyContract: reading.historyContract,
        isQualityValid: reading.isQualityValid,
        measurementResolution: reading.measurementResolution,
        reportedDeltaCm24h: reading.reportedDeltaCm24h,
        waterTemperatureC: reading.waterTemperatureC,
        forecast: reading.forecast,
        forecastUpdatedAt: reading.forecastUpdatedAt,
      );
    }

    final difference = reading.value - previous.value;
    final resolutions = <double>[
      if (reading.measurementResolution case final value?
          when value.isFinite && value > 0)
        value,
      if (previous.measurementResolution case final value?
          when value.isFinite && value > 0)
        value,
    ];
    final resolution = resolutions.isEmpty
        ? null
        : resolutions.reduce((a, b) => a > b ? a : b);
    final trend = waterTrendFromRealDelta(
      difference,
      measurementResolution: resolution,
    )!;
    return WaterLevel(
      stationId: reading.stationId,
      value: reading.value,
      timestamp: reading.timestamp,
      freshnessTimestamp: reading.freshnessTimestamp,
      measurementPrecision: reading.measurementPrecision,
      trend: trend,
      source: reading.source,
      unit: reading.unit,
      sourceName: reading.sourceName,
      hasKnownTrend: true,
      metricCode: reading.metricCode,
      measurementDatum: reading.measurementDatum,
      historyContract: reading.historyContract,
      isQualityValid: reading.isQualityValid,
      measurementResolution: reading.measurementResolution,
      reportedDeltaCm24h: reading.reportedDeltaCm24h,
      waterTemperatureC: reading.waterTemperatureC,
      forecast: reading.forecast,
      forecastUpdatedAt: reading.forecastUpdatedAt,
    );
  }

  static WaterLevel _copyWithResolvedTrend(
    WaterLevel reading,
    WaterTrend? trend,
  ) {
    return WaterLevel(
      stationId: reading.stationId,
      value: reading.value,
      timestamp: reading.timestamp,
      freshnessTimestamp: reading.freshnessTimestamp,
      measurementPrecision: reading.measurementPrecision,
      trend: trend ?? WaterTrend.stable,
      source: reading.source,
      unit: reading.unit,
      sourceName: reading.sourceName,
      hasKnownTrend: trend != null,
      metricCode: reading.metricCode,
      measurementDatum: reading.measurementDatum,
      historyContract: reading.historyContract,
      isQualityValid: reading.isQualityValid,
      measurementResolution: reading.measurementResolution,
      reportedDeltaCm24h: reading.reportedDeltaCm24h,
      waterTemperatureC: reading.waterTemperatureC,
      forecast: reading.forecast,
      forecastUpdatedAt: reading.forecastUpdatedAt,
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
