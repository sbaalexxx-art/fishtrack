import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/station.dart';
import '../models/water_level.dart';
import 'afdj_water_provider.dart';
import 'danube_fis_water_provider.dart';
import 'danube_his_water_provider.dart';

abstract interface class OfficialWaterDataSource {
  WaterLevelSource get source;

  Future<List<WaterLevel>> getHistory(
    String stationId, {
    String? stationName,
    int limit = 30,
  });
}

abstract interface class DailyWaterSnapshotReader {
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  });
}

class SupabaseDailyWaterSnapshotReader implements DailyWaterSnapshotReader {
  const SupabaseDailyWaterSnapshotReader();

  @override
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  }) async {
    final rows = await Supabase.instance.client
        .from('daily_water_snapshots')
        .select(
          'station_id,observation_date,level_cm,level_source,'
          'level_measured_at,quality',
        )
        .eq('station_id', stationId)
        .order('level_measured_at', ascending: false)
        .limit(limit);
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}

enum WaterHistoryResultStatus {
  success,
  insufficientHistory,
  providerError,
  unavailable,
}

class WaterHistoryResult {
  const WaterHistoryResult({
    required this.status,
    required this.readings,
    required this.source,
    required this.hadProviderError,
    this.safeDiagnosticMessage,
  });

  final WaterHistoryResultStatus status;
  final List<WaterLevel> readings;
  final WaterLevelSource? source;
  final bool hadProviderError;
  final String? safeDiagnosticMessage;
}

class WaterRepository implements OfficialWaterDataSource {
  const WaterRepository({
    this.afdjProvider = const AfdjWaterProvider(),
    this.danubeHisProvider = const DanubeHisWaterProvider(),
    this.danubeFisProvider = const DanubeFisWaterProvider(),
    this.snapshotReader = const SupabaseDailyWaterSnapshotReader(),
  });

  final AfdjWaterProvider afdjProvider;
  final DanubeHisWaterProvider danubeHisProvider;
  final DanubeFisWaterProvider danubeFisProvider;
  final DailyWaterSnapshotReader snapshotReader;

  static const defaultFreshnessThreshold = Duration(hours: 36);
  static const maxSnapshotHistoryPoints = 30;

  static const officialAfdjStationOrder = <String>[
    'Baziaș',
    'Moldova Veche',
    'Drencova',
    'Orșova',
    'Drobeta Turnu Severin',
    'Gruia',
    'Cetate',
    'Calafat',
    'Rast',
    'Bechet',
    'Corabia',
    'Turnu Măgurele',
    'Zimnicea',
    'Giurgiu',
    'Oltenița',
    'Călărași',
    'Cernavodă',
    'Hârșova',
    'Brăila',
    'Galați',
    'Isaccea',
    'Tulcea',
    'Sulina',
  ];

  // Metadata-only fallbacks for official AFDJ stations missing from the
  // current Supabase seed. Coordinates are published by AFDJ; levels remain
  // unavailable until a real reading exists.
  static final _missingSeedStations = <String, Station>{
    _normalizedName('Drencova'): Station(
      id: 'afdj-drencova',
      name: 'Drencova',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.6377707,
      longitude: 21.9723364,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    _normalizedName('Gruia'): Station(
      id: 'afdj-gruia',
      name: 'Gruia',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.2665732,
      longitude: 22.7046852,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    _normalizedName('Cetate'): Station(
      id: 'afdj-cetate',
      name: 'Cetate',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 44.1114259,
      longitude: 23.0475514,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
    _normalizedName('Rast'): Station(
      id: 'afdj-rast',
      name: 'Rast',
      river: 'Dunărea',
      level: 0,
      trend: WaterTrend.stable,
      latitude: 43.8851672,
      longitude: 23.2813472,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    ),
  };

  @override
  WaterLevelSource get source => WaterLevelSource.manualFallback;

  Future<List<Station>> getStations() async {
    final stationRows = await _getStationRows();
    Map<String, List<WaterLevel>> afdjLevels = const {};
    try {
      afdjLevels = await afdjProvider.getLevels(
        stationRows.map((row) => row['name']?.toString() ?? ''),
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('AFDJ levels', error, stackTrace);
      final reason = _providerFailureReason(error);
      for (final row in stationRows) {
        _logAfdjNotSelected(row['name']?.toString() ?? 'Unknown', reason);
      }
    }
    Map<String, List<WaterLevel>> danubeHisLevels = const {};
    try {
      danubeHisLevels = await danubeHisProvider.getLevels(
        stationRows.map((row) => row['name']?.toString() ?? ''),
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('DanubeHIS levels', error, stackTrace);
    }
    Map<String, List<WaterLevel>> danubeFisLevels = const {};
    try {
      danubeFisLevels = await danubeFisProvider.getLevels(
        stationRows.map((row) => row['name']?.toString() ?? ''),
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('DanubeFIS levels', error, stackTrace);
    }

    return _stationsFromRows(
      stationRows,
      afdjLevels: afdjLevels,
      danubeHisLevels: danubeHisLevels,
      danubeFisLevels: danubeFisLevels,
    );
  }

  Future<List<Station>> getFastStations() async {
    final stationRows = await _getStationRows();
    Map<String, List<WaterLevel>> danubeFisLevels = const {};
    try {
      danubeFisLevels = await danubeFisProvider.getLevels(
        stationRows.map((row) => row['name']?.toString() ?? ''),
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('DanubeFIS fast levels', error, stackTrace);
    }

    return _stationsFromRows(
      stationRows,
      afdjLevels: const {},
      danubeHisLevels: const {},
      danubeFisLevels: danubeFisLevels,
    );
  }

  Future<List<Map<String, dynamic>>> _getStationRows() async {
    final client = Supabase.instance.client;
    late final List<Map<String, dynamic>> stationRows;
    try {
      stationRows = await client
          .from('stations')
          .select()
          .timeout(const Duration(seconds: 12));
    } on Exception catch (error, stackTrace) {
      _logFailure('station metadata', error, stackTrace);
      rethrow;
    }
    return stationRows;
  }

  List<Station> _stationsFromRows(
    List<Map<String, dynamic>> stationRows, {
    required Map<String, List<WaterLevel>> afdjLevels,
    required Map<String, List<WaterLevel>> danubeHisLevels,
    required Map<String, List<WaterLevel>> danubeFisLevels,
  }) {
    final stationsByName = stationRows
        .map((row) {
          final data = Map<String, dynamic>.from(row);
          final stationName = data['name']?.toString() ?? '';
          final externalReadings =
              danubeHisLevels[DanubeHisWaterProvider.normalizedName(
                stationName,
              )] ??
              const [];
          final afdjReadings =
              afdjLevels[DanubeHisWaterProvider.normalizedName(stationName)] ??
              const [];
          final fisReadings =
              danubeFisLevels[DanubeHisWaterProvider.normalizedName(
                stationName,
              )] ??
              const [];
          final providerReadings = _selectCurrentProviderReadings(
            stationName,
            afdjReadings,
            externalReadings,
            fisReadings,
          );
          final readings = providerReadings;
          if (providerReadings.isEmpty) {
            _logProviderFallback(stationName, 'no valid provider reading');
          }
          if (readings.isNotEmpty) {
            final latest = readings.first;
            data['level'] = latest.value;
            data['last_update'] = latest.timestamp.toIso8601String();
            final trend = _trendFromHistory(readings);
            data['trend'] = (trend ?? WaterTrend.stable).name;
            data['has_known_trend'] = trend != null;
            data['has_water_level'] = true;
            data['water_level_unit'] = latest.unit;
            data['water_level_source'] = latest.source.name;
          } else {
            data['has_water_level'] = false;
          }
          return Station.tryFromJson(data);
        })
        .whereType<Station>()
        .fold<Map<String, Station>>({}, (stations, station) {
          stations[_normalizedName(station.name)] = station;
          return stations;
        });

    return officialAfdjStationOrder
        .map((name) {
          final key = _normalizedName(name);
          return stationsByName[key] ?? _missingSeedStations[key];
        })
        .whereType<Station>()
        .toList(growable: false);
  }

  @override
  Future<List<WaterLevel>> getHistory(
    String stationId, {
    String? stationName,
    int limit = 30,
  }) async => (await getHistoryResult(
    stationId,
    stationName: stationName,
    limit: limit,
  )).readings;

  Future<WaterHistoryResult> getSnapshotHistoryResult(
    String stationId, {
    int limit = maxSnapshotHistoryPoints,
  }) async {
    final requestedLimit = limit <= 0
        ? 0
        : limit > maxSnapshotHistoryPoints
        ? maxSnapshotHistoryPoints
        : limit;
    if (stationId.trim().isEmpty || requestedLimit == 0) {
      return const WaterHistoryResult(
        status: WaterHistoryResultStatus.unavailable,
        readings: <WaterLevel>[],
        source: null,
        hadProviderError: false,
      );
    }

    try {
      final rows = await snapshotReader.readStationHistory(
        stationId,
        limit: requestedLimit,
      );
      final readingsByObservationDate = <String, WaterLevel>{};
      for (final row in rows) {
        final reading = _snapshotReading(row, expectedStationId: stationId);
        if (reading == null) continue;
        final observationDate = row['observation_date']?.toString().trim();
        if (observationDate == null || observationDate.isEmpty) continue;
        final existing = readingsByObservationDate[observationDate];
        if (existing == null || reading.timestamp.isAfter(existing.timestamp)) {
          readingsByObservationDate[observationDate] = reading;
        }
      }

      final chronological = readingsByObservationDate.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final limited = chronological.length <= requestedLimit
          ? chronological
          : chronological.sublist(chronological.length - requestedLimit);
      final readings = _withCalculatedTrends(limited, stationId);
      if (readings.isEmpty) {
        return const WaterHistoryResult(
          status: WaterHistoryResultStatus.unavailable,
          readings: <WaterLevel>[],
          source: null,
          hadProviderError: false,
        );
      }

      return WaterHistoryResult(
        status: readings.length >= 2
            ? WaterHistoryResultStatus.success
            : WaterHistoryResultStatus.insufficientHistory,
        readings: List<WaterLevel>.unmodifiable(readings),
        source: readings.last.source,
        hadProviderError: false,
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('daily water snapshots', error, stackTrace);
      return const WaterHistoryResult(
        status: WaterHistoryResultStatus.unavailable,
        readings: <WaterLevel>[],
        source: null,
        hadProviderError: false,
        safeDiagnosticMessage: 'Daily water snapshot history is unavailable',
      );
    }
  }

  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) async {
    final snapshotResult = await getSnapshotHistoryResult(
      stationId,
      limit: limit,
    );
    final failedProviders = <String>[];
    List<WaterLevel> liveReadings = const <WaterLevel>[];
    if (stationName != null && stationName.trim().isNotEmpty) {
      final normalized = DanubeHisWaterProvider.normalizedName(stationName);
      List<WaterLevel> afdjReadings = const [];
      List<WaterLevel> hisReadings = const [];
      List<WaterLevel> fisReadings = const [];
      try {
        final result = await afdjProvider.getLevels([stationName]);
        afdjReadings = result[normalized] ?? const [];
      } on Exception catch (error, stackTrace) {
        failedProviders.add('AFDJ');
        _logFailure('AFDJ history', error, stackTrace);
        _logAfdjNotSelected(stationName, _providerFailureReason(error));
      }
      try {
        final result = await danubeHisProvider.getLevels([
          stationName,
        ], limit: limit);
        hisReadings = result[normalized] ?? const [];
      } on Exception catch (error, stackTrace) {
        failedProviders.add('DanubeHIS');
        _logFailure('DanubeHIS history', error, stackTrace);
      }
      try {
        if (prefetchedCurrentReading != null &&
            prefetchedCurrentReading.source == WaterLevelSource.danubeFis &&
            _isValidReading(prefetchedCurrentReading) &&
            prefetchedCurrentReading.unit.toLowerCase() == 'cm') {
          fisReadings = [prefetchedCurrentReading];
        } else {
          final result = await danubeFisProvider.getLevels([stationName]);
          fisReadings = result[normalized] ?? const [];
        }
      } on Exception catch (error, stackTrace) {
        failedProviders.add('DanubeFIS');
        _logFailure('DanubeFIS history', error, stackTrace);
      }
      final selectedReadings = _selectProviderReadings(
        stationName,
        afdjReadings,
        hisReadings,
        fisReadings,
      );
      liveReadings = selectedReadings;
    }

    final readings = _mergeSnapshotHistoryWithLiveReadings(
      stationId,
      snapshotResult.readings,
      liveReadings,
    );
    if (readings.isNotEmpty) {
      return WaterHistoryResult(
        status: readings.length >= 2
            ? WaterHistoryResultStatus.success
            : WaterHistoryResultStatus.insufficientHistory,
        readings: List<WaterLevel>.unmodifiable(readings),
        source: liveReadings.isNotEmpty
            ? liveReadings.first.source
            : readings.last.source,
        hadProviderError: failedProviders.isNotEmpty,
        safeDiagnosticMessage:
            _safeProviderDiagnostic(failedProviders) ??
            snapshotResult.safeDiagnosticMessage,
      );
    }

    _logProviderFallback(
      stationName ?? stationId,
      'no live or snapshot history',
    );
    return WaterHistoryResult(
      status: failedProviders.isNotEmpty
          ? WaterHistoryResultStatus.providerError
          : WaterHistoryResultStatus.unavailable,
      readings: const [],
      source: null,
      hadProviderError: failedProviders.isNotEmpty,
      safeDiagnosticMessage: _safeProviderDiagnostic(failedProviders),
    );
  }

  Future<WaterHistoryResult> getCanonicalSourceHistory(
    String stationId, {
    required String stationName,
    required WaterLevelSource source,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required int limit,
  }) async {
    if (limit <= 0 || rangeEnd.isBefore(rangeStart)) {
      return WaterHistoryResult(
        status: WaterHistoryResultStatus.unavailable,
        readings: const <WaterLevel>[],
        source: source,
        hadProviderError: false,
        safeDiagnosticMessage: 'Invalid canonical history range or limit',
      );
    }

    final normalized = DanubeHisWaterProvider.normalizedName(stationName);
    late final List<WaterLevel> providerReadings;
    try {
      providerReadings = switch (source) {
        WaterLevelSource.afdj =>
          (await afdjProvider.getLevels([stationName]))[normalized] ?? const [],
        WaterLevelSource.danubeHis =>
          (await danubeHisProvider.getLevels([
                stationName,
              ], limit: limit))[normalized] ??
              const [],
        WaterLevelSource.danubeFis =>
          (await danubeFisProvider.getLevels([stationName]))[normalized] ??
              const [],
        WaterLevelSource.inhga || WaterLevelSource.manualFallback => const [],
      };
    } on Exception catch (error, stackTrace) {
      _logFailure(
        '${_sourceLabel(source)} canonical history',
        error,
        stackTrace,
      );
      return WaterHistoryResult(
        status: WaterHistoryResultStatus.providerError,
        readings: const <WaterLevel>[],
        source: source,
        hadProviderError: true,
        safeDiagnosticMessage:
            '${_sourceLabel(source)} canonical history request failed',
      );
    }

    final readingsByTimestamp = <int, WaterLevel>{};
    for (final reading in providerReadings) {
      if (!_isValidReading(reading) || reading.source != source) continue;
      if (reading.timestamp.isBefore(rangeStart) ||
          reading.timestamp.isAfter(rangeEnd)) {
        continue;
      }
      readingsByTimestamp.putIfAbsent(
        reading.timestamp.toUtc().microsecondsSinceEpoch,
        () => reading,
      );
    }
    final chronological = readingsByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final limited = chronological.length <= limit
        ? chronological
        : chronological.sublist(chronological.length - limit);
    if (limited.isEmpty) {
      return WaterHistoryResult(
        status: WaterHistoryResultStatus.unavailable,
        readings: const <WaterLevel>[],
        source: source,
        hadProviderError: false,
        safeDiagnosticMessage:
            'No compatible ${_sourceLabel(source)} history for $stationId',
      );
    }

    return WaterHistoryResult(
      status: limited.length >= 2
          ? WaterHistoryResultStatus.success
          : WaterHistoryResultStatus.insufficientHistory,
      readings: List<WaterLevel>.unmodifiable(limited),
      source: source,
      hadProviderError: false,
    );
  }

  static WaterLevel? _snapshotReading(
    Map<String, Object?> row, {
    required String expectedStationId,
  }) {
    if (row['station_id']?.toString() != expectedStationId ||
        !_snapshotQualityIsUsable(row['quality'])) {
      return null;
    }
    final level = row['level_cm'] is num
        ? (row['level_cm'] as num).toDouble()
        : double.tryParse(row['level_cm']?.toString() ?? '');
    final measuredAt = DateTime.tryParse(
      row['level_measured_at']?.toString() ?? '',
    );
    final source = _snapshotSource(row['level_source']);
    if (level == null ||
        !level.isFinite ||
        measuredAt == null ||
        measuredAt.millisecondsSinceEpoch <= 0 ||
        source == null) {
      return null;
    }
    return WaterLevel(
      stationId: expectedStationId,
      value: level,
      timestamp: measuredAt,
      trend: WaterTrend.stable,
      source: source,
      unit: 'cm',
      sourceName: _sourceLabel(source),
    );
  }

  static bool _snapshotQualityIsUsable(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'valid' || 'partial' || 'stale' => true,
        _ => false,
      };

  static WaterLevelSource? _snapshotSource(Object? value) {
    final source = WaterLevelSource.parse(value);
    return source == WaterLevelSource.manualFallback ? null : source;
  }

  static List<WaterLevel> _mergeSnapshotHistoryWithLiveReadings(
    String stationId,
    List<WaterLevel> snapshots,
    List<WaterLevel> liveReadings,
  ) {
    final readingsByDate = <String, WaterLevel>{};
    for (final reading in [...snapshots, ...liveReadings]) {
      if (!_isValidReading(reading)) continue;
      final dateKey = reading.timestamp.toUtc().toIso8601String().substring(
        0,
        10,
      );
      final existing = readingsByDate[dateKey];
      if (existing == null || reading.timestamp.isAfter(existing.timestamp)) {
        readingsByDate[dateKey] = WaterLevel(
          stationId: stationId,
          value: reading.value,
          timestamp: reading.timestamp,
          trend: reading.trend,
          source: reading.source,
          unit: reading.unit,
          sourceName: reading.sourceName,
          hasKnownTrend: reading.hasKnownTrend,
        );
      }
    }
    final chronological = readingsByDate.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final limited = chronological.length <= maxSnapshotHistoryPoints
        ? chronological
        : chronological.sublist(
            chronological.length - maxSnapshotHistoryPoints,
          );
    return List<WaterLevel>.unmodifiable(
      _withCalculatedTrends(limited, stationId),
    );
  }

  static List<WaterLevel> _withCalculatedTrends(
    List<WaterLevel> readings,
    String stationId,
  ) {
    return List.generate(readings.length, (index) {
      final reading = readings[index];
      final trend = reading.hasKnownTrend
          ? reading.trend
          : index > 0 && readings[index - 1].source == reading.source
          ? _trendFromHistory([reading, readings[index - 1]])
          : null;
      return WaterLevel(
        stationId: stationId,
        value: reading.value,
        timestamp: reading.timestamp,
        trend: trend ?? WaterTrend.stable,
        source: reading.source,
        unit: reading.unit,
        sourceName: reading.sourceName,
        hasKnownTrend: reading.hasKnownTrend || trend != null,
      );
    }, growable: false);
  }

  static WaterTrend? _trendFromHistory(List<WaterLevel> readings) {
    if (readings.isEmpty) return null;
    if (readings.first.hasKnownTrend) return readings.first.trend;
    if (readings.length < 2) return null;
    final difference = readings[0].value - readings[1].value;
    if (difference.abs() <= .01) return WaterTrend.stable;
    return difference > 0 ? WaterTrend.rising : WaterTrend.falling;
  }

  static List<WaterLevel> _selectCurrentProviderReadings(
    String stationName,
    List<WaterLevel> afdj,
    List<WaterLevel> danubeHis,
    List<WaterLevel> danubeFis,
  ) {
    final providers = [
      _validNewestFirst(afdj),
      _validNewestFirst(danubeHis),
      _validNewestFirst(danubeFis),
    ];
    final afdjReadings = providers[0];
    final now = DateTime.now();

    if (afdjReadings.isNotEmpty &&
        _isWithinDefaultFreshness(afdjReadings.first, now)) {
      _logProviderUsed(
        stationName,
        afdjReadings.first,
        'AFDJ primary reading is within freshness tolerance',
      );
      return [
        afdjReadings.first,
        ...providers[1]
            .where(
              (reading) =>
                  reading.timestamp.isBefore(afdjReadings.first.timestamp),
            )
            .take(13),
      ];
    }

    WaterLevel? freshestReading;
    var freshestProviderIndex = -1;
    for (var index = 0; index < providers.length; index++) {
      if (providers[index].isEmpty) continue;
      final candidate = providers[index].first;
      if (freshestReading == null ||
          candidate.timestamp.isAfter(freshestReading.timestamp)) {
        freshestReading = candidate;
        freshestProviderIndex = index;
      }
    }

    if (freshestReading == null) {
      developer.log(
        'Unmatched station: $stationName; no valid provider reading',
        name: 'AIFishMap.Water',
      );
      return const [];
    }

    final reason = afdjReadings.isEmpty
        ? 'AFDJ unavailable; freshest valid provider reading selected'
        : 'AFDJ reading exceeded freshness tolerance; freshest valid '
              'provider reading selected';
    if (freshestProviderIndex != 0) {
      _logAfdjNotSelected(stationName, reason);
    }
    _logProviderUsed(stationName, freshestReading, reason);

    return switch (freshestProviderIndex) {
      0 => [
        freshestReading,
        ...providers[1]
            .where(
              (reading) =>
                  reading.timestamp.isBefore(freshestReading!.timestamp),
            )
            .take(13),
      ],
      1 => providers[1].take(14).toList(growable: false),
      2 => providers[2],
      _ => const [],
    };
  }

  static List<WaterLevel> _validNewestFirst(List<WaterLevel> readings) {
    final valid = readings.where(_isValidReading).toList(growable: false);
    valid.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return valid;
  }

  static bool _isValidReading(WaterLevel reading) {
    final timestamp = reading.timestamp.toUtc();
    return reading.value.isFinite &&
        timestamp.millisecondsSinceEpoch > 0 &&
        !timestamp.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );
  }

  static bool _isWithinDefaultFreshness(WaterLevel reading, DateTime now) {
    final age = now.toUtc().difference(reading.timestamp.toUtc());
    return age >= const Duration(minutes: -5) &&
        age <= defaultFreshnessThreshold;
  }

  static String? _safeProviderDiagnostic(List<String> failedProviders) =>
      failedProviders.isEmpty
      ? null
      : 'Provider request failed: ${failedProviders.join(', ')}';

  static List<WaterLevel> _selectProviderReadings(
    String stationName,
    List<WaterLevel> afdj,
    List<WaterLevel> danubeHis,
    List<WaterLevel> danubeFis,
  ) {
    if (afdj.isNotEmpty) {
      _logProviderUsed(stationName, afdj.first, 'AFDJ primary available');
      return [
        afdj.first,
        ...danubeHis.where(
          (reading) => reading.timestamp.isBefore(afdj.first.timestamp),
        ),
      ];
    }
    if (danubeHis.isNotEmpty) {
      _logAfdjNotSelected(stationName, 'no valid AFDJ reading matched');
      _logProviderUsed(stationName, danubeHis.first, 'AFDJ unavailable');
      return danubeHis;
    }
    if (danubeFis.isNotEmpty) {
      _logAfdjNotSelected(stationName, 'no valid AFDJ reading matched');
      _logProviderUsed(
        stationName,
        danubeFis.first,
        'AFDJ and DanubeHIS unavailable',
      );
      return danubeFis;
    }
    developer.log(
      'Unmatched station: $stationName; no provider reading',
      name: 'AIFishMap.Water',
    );
    return const [];
  }

  static String _providerFailureReason(Object error) =>
      error is AfdjProviderException ? error.message : error.toString();

  static String _sourceLabel(WaterLevelSource source) => switch (source) {
    WaterLevelSource.afdj => 'AFDJ',
    WaterLevelSource.danubeHis => 'DanubeHIS',
    WaterLevelSource.danubeFis => 'DanubeFIS',
    WaterLevelSource.inhga => 'INHGA',
    WaterLevelSource.manualFallback => 'Manual',
  };

  static void _logAfdjNotSelected(String stationName, String reason) {
    developer.log(
      'AFDJ not selected: $stationName; reason: $reason',
      name: 'AIFishMap.Water',
    );
  }

  static void _logProviderUsed(
    String stationName,
    WaterLevel reading,
    String reason,
  ) {
    final age = DateTime.now().difference(reading.timestamp.toLocal());
    final ageMinutes = age.isNegative ? 0 : age.inMinutes;
    developer.log(
      'Provider used: ${reading.sourceName}; station matched: $stationName; '
      'timestamp age: ${ageMinutes}m; reason: $reason',
      name: 'AIFishMap.Water',
    );
  }

  static void _logProviderFallback(String stationName, String reason) {
    developer.log(
      'Provider fallback: $stationName; reason: $reason',
      name: 'AIFishMap.Water',
    );
  }

  static void _logFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    developer.log(
      '$operation loading failed',
      name: 'AIFishMap.Water',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static String _normalizedName(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[ăâáàä]'), 'a')
      .replaceAll(RegExp('[îíìï]'), 'i')
      .replaceAll(RegExp('[șş]'), 's')
      .replaceAll(RegExp('[țţ]'), 't')
      .replaceAll(RegExp('[^a-z0-9]'), '');
}
