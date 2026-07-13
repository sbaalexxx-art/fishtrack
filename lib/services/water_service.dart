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
  static const _maxBatchConcurrency = 4;
  static final StreamController<Station> _stationSelectionController =
      StreamController<Station>.broadcast(sync: true);
  static final TimedCache<List<Station>> _stationsCache =
      TimedCache<List<Station>>(duration: cacheDuration);
  static final Map<String, TimedCache<List<WaterLevel>>> _historyCache = {};
  static final Map<String, TimedCache<WaterHistoryResult>>
  _stationDetailsHistoryCache = {};
  static final Map<String, _WaterUiCacheEntry> _waterUiCache = {};
  static final Map<String, WaterUiResult> _lastKnownGoodByStation = {};
  static final Map<String, Future<WaterUiResult>> _waterUiInFlight = {};
  static final Map<String, int> _waterUiKeyGenerations = {};
  static int _waterUiCacheEpoch = 0;
  static int _progressiveBatchGeneration = 0;
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
    _stationDetailsHistoryCache.clear();
    _waterUiCacheEpoch++;
    _waterUiCache.clear();
    _lastKnownGoodByStation.clear();
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

    final historyResult = await _getStationDetailsHistory(
      station,
      source: source,
      range: range,
      forceRefresh: forceRefresh,
    );
    final currentTimestamp = current.timestamp.toUtc().microsecondsSinceEpoch;
    final readingsByTimestamp = <int, WaterLevel>{};
    for (final reading in historyResult.readings) {
      if (!_isValidReading(reading) || reading.source != source) continue;
      if (reading.timestamp.isAfter(current.timestamp)) continue;
      readingsByTimestamp[reading.timestamp.toUtc().microsecondsSinceEpoch] =
          reading;
    }
    readingsByTimestamp[currentTimestamp] = current;
    final history = readingsByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final hasTrend = history.length >= 2;
    final dailyDeltaCm =
        hasTrend &&
            history[history.length - 2].unit.toLowerCase() == 'cm' &&
            history.last.unit.toLowerCase() == 'cm'
        ? history.last.value - history[history.length - 2].value
        : null;
    final trend = dailyDeltaCm == null
        ? null
        : dailyDeltaCm > 0
        ? WaterTrend.rising
        : dailyDeltaCm < 0
        ? WaterTrend.falling
        : WaterTrend.stable;

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
        historyResult,
        pointCount: history.length,
      ),
      dailyDeltaCm: dailyDeltaCm,
      trend: trend,
      safeDiagnosticMessage:
          historyResult.safeDiagnosticMessage ??
          currentResult.safeDiagnosticMessage,
    );
  }

  Future<WaterHistoryResult> _getStationDetailsHistory(
    Station station, {
    required WaterLevelSource source,
    required WaterStationDetailsRange range,
    required bool forceRefresh,
  }) async {
    final key =
        '${identityHashCode(_repository)}:${station.id}:'
        '${source.name}:${range.name}:${range.historyLimit}';
    final cache = _stationDetailsHistoryCache.putIfAbsent(
      key,
      () => TimedCache<WaterHistoryResult>(duration: cacheDuration),
    );
    return (await cache.get(() {
      final rangeEnd = DateTime.now();
      return _repository.getCanonicalSourceHistory(
        station.id,
        stationName: station.name,
        source: source,
        rangeStart: rangeEnd.subtract(range.duration),
        rangeEnd: rangeEnd,
        limit: range.historyLimit,
      );
    }, forceRefresh: forceRefresh)).value;
  }

  static WaterStationDetailsHistoryStatus _stationDetailsHistoryStatus(
    WaterHistoryResult result, {
    required int pointCount,
  }) {
    if (result.status == WaterHistoryResultStatus.providerError) {
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
    if (forceRefresh) {
      _waterUiCache.remove(key);
      _waterUiInFlight.remove(key);
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
      final activeRequest = _waterUiInFlight[key];
      if (activeRequest != null) return activeRequest;
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
    WaterLevelSource.danubeFis ||
    WaterLevelSource.inhga => true,
    WaterLevelSource.manualFallback => false,
  };

  static bool _isValidReading(WaterLevel reading) =>
      reading.value.isFinite && reading.timestamp.millisecondsSinceEpoch > 0;

  static Duration _nonNegativeAge(DateTime now, DateTime timestamp) {
    final age = now.difference(timestamp.toLocal());
    return age.isNegative ? Duration.zero : age;
  }
}
