import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/water/water_history_analysis.dart';
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

abstract interface class StationMetadataReader {
  Future<List<Map<String, dynamic>>> readStations();
}

class SupabaseStationMetadataReader implements StationMetadataReader {
  const SupabaseStationMetadataReader();

  @override
  Future<List<Map<String, dynamic>>> readStations() async {
    final rows = await Supabase.instance.client.from('stations').select();
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}

abstract interface class DailyWaterSnapshotReader {
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  });

  Future<List<Map<String, Object?>>> readRecentStationTrends(
    Iterable<String> stationIds, {
    required DateTime notBefore,
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

  @override
  Future<List<Map<String, Object?>>> readRecentStationTrends(
    Iterable<String> stationIds, {
    required DateTime notBefore,
  }) async {
    final ids = stationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <Map<String, Object?>>[];

    final notBeforeDate = notBefore.toUtc().toIso8601String().substring(0, 10);
    final rows = await Supabase.instance.client
        .from('daily_water_snapshots')
        .select(
          'station_id,observation_date,daily_delta_cm,delta_source,'
          'delta_measured_at,delta_method,quality',
        )
        .inFilter('station_id', ids)
        .gte('observation_date', notBeforeDate)
        .order('observation_date', ascending: false);
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }
}

abstract interface class WaterMobileContractReader {
  Future<List<Map<String, dynamic>>> readLatestStations({String? stationId});

  Future<List<Map<String, dynamic>>> readStationHistory(
    String stationId, {
    required int days,
  });
}

class SupabaseWaterMobileContractReader implements WaterMobileContractReader {
  const SupabaseWaterMobileContractReader();

  @override
  Future<List<Map<String, dynamic>>> readLatestStations({
    String? stationId,
  }) async {
    final response = await Supabase.instance.client.rpc(
      'get_water_station_latest_v2',
      params: <String, Object?>{'p_station_id': stationId},
    );
    return _rows(response);
  }

  @override
  Future<List<Map<String, dynamic>>> readStationHistory(
    String stationId, {
    required int days,
  }) async {
    final response = await Supabase.instance.client.rpc(
      'get_water_station_history_v2',
      params: <String, Object?>{'p_station_id': stationId, 'p_days': days},
    );
    return _rows(response);
  }

  static List<Map<String, dynamic>> _rows(Object? response) {
    if (response is! List) return const <Map<String, dynamic>>[];

    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
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
    this.stationMetadataReader = const SupabaseStationMetadataReader(),
    this.snapshotReader = const SupabaseDailyWaterSnapshotReader(),
    this.mobileContractReader = const SupabaseWaterMobileContractReader(),
  });

  final AfdjWaterProvider afdjProvider;
  final DanubeHisWaterProvider danubeHisProvider;
  final DanubeFisWaterProvider danubeFisProvider;
  final StationMetadataReader stationMetadataReader;
  final DailyWaterSnapshotReader snapshotReader;
  final WaterMobileContractReader mobileContractReader;

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

  @override
  WaterLevelSource get source => WaterLevelSource.manualFallback;

  Future<List<Station>> getStations() async {
    try {
      final rows = await mobileContractReader.readLatestStations();
      final stations = await _stationsFromMobileContract(rows);

      if (stations.isNotEmpty) {
        return stations;
      }

      _logProviderFallback(
        'Water mobile contract',
        'the backend returned no valid station rows',
      );
    } catch (error, stackTrace) {
      _logFailure('Water mobile latest contract', error, stackTrace);
    }

    return _getStationsFromDirectProviders();
  }

  Future<List<Station>> getFastStations() => getStations();
  Future<List<Station>> _getStationsFromDirectProviders() async {
    final stationRows = await _getStationRows();
    final snapshotTrendsFuture = _loadRecentSnapshotTrends(stationRows);
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
      snapshotTrendsByStationId: await snapshotTrendsFuture,
    );
  }

  Future<Map<String, WaterTrend>> _loadRecentSnapshotTrends(
    List<Map<String, dynamic>> stationRows,
  ) async {
    final stationIds = stationRows
        .map((row) => row['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (stationIds.isEmpty) return const <String, WaterTrend>{};

    final now = DateTime.now().toUtc();
    try {
      final rows = await snapshotReader.readRecentStationTrends(
        stationIds,
        notBefore: now.subtract(defaultFreshnessThreshold),
      );
      return _snapshotTrendsFromRows(rows, now: now);
    } on Exception catch (error, stackTrace) {
      _logFailure('daily water snapshot trends', error, stackTrace);
      return const <String, WaterTrend>{};
    }
  }

  static Map<String, WaterTrend> _snapshotTrendsFromRows(
    List<Map<String, Object?>> rows, {
    required DateTime now,
  }) {
    final latest = <String, ({WaterTrend trend, DateTime measuredAt})>{};
    for (final row in rows) {
      final stationId = row['station_id']?.toString().trim() ?? '';
      final quality = row['quality']?.toString().trim().toLowerCase();
      final method = row['delta_method']?.toString().trim().toLowerCase();
      final delta = row['daily_delta_cm'] is num
          ? (row['daily_delta_cm'] as num).toDouble()
          : double.tryParse(row['daily_delta_cm']?.toString() ?? '');
      final measuredAt = DateTime.tryParse(
        row['delta_measured_at']?.toString() ?? '',
      );
      final source = _snapshotSource(row['delta_source']);
      if (stationId.isEmpty ||
          (quality != 'valid' && quality != 'partial') ||
          (method != 'provider_reported' && method != 'computed_same_source') ||
          delta == null ||
          !delta.isFinite ||
          measuredAt == null ||
          measuredAt.millisecondsSinceEpoch <= 0 ||
          source == null) {
        continue;
      }

      final measuredAtUtc = measuredAt.toUtc();
      final age = now.difference(measuredAtUtc);
      if (age < const Duration(minutes: -5) ||
          age > defaultFreshnessThreshold) {
        continue;
      }

      final trend = delta == 0
          ? WaterTrend.stable
          : delta > 0
          ? WaterTrend.rising
          : WaterTrend.falling;
      final existing = latest[stationId];
      if (existing == null || measuredAtUtc.isAfter(existing.measuredAt)) {
        latest[stationId] = (trend: trend, measuredAt: measuredAtUtc);
      }
    }

    return Map<String, WaterTrend>.unmodifiable({
      for (final entry in latest.entries) entry.key: entry.value.trend,
    });
  }

  Future<List<Map<String, dynamic>>> _getStationRows() async {
    try {
      return await stationMetadataReader.readStations().timeout(
        const Duration(seconds: 12),
      );
    } on Exception catch (error, stackTrace) {
      _logFailure('station metadata', error, stackTrace);
      rethrow;
    }
  }

  List<Station> _stationsFromRows(
    List<Map<String, dynamic>> stationRows, {
    required Map<String, List<WaterLevel>> afdjLevels,
    required Map<String, List<WaterLevel>> danubeHisLevels,
    required Map<String, List<WaterLevel>> danubeFisLevels,
    required Map<String, WaterTrend> snapshotTrendsByStationId,
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
            data['water_freshness_timestamp'] = latest
                .effectiveFreshnessTimestamp
                .toIso8601String();
            data['has_water_level'] = true;
            data['water_level_unit'] = latest.unit;
            data['water_level_source'] = latest.source.name;
            data['water_measurement_precision'] =
                latest.measurementPrecision.name;
          } else {
            data['has_water_level'] = false;
          }

          final stationId = data['id']?.toString().trim() ?? '';
          final liveTrend = readings.isEmpty
              ? null
              : _trendFromHistory(readings);
          final effectiveTrend =
              liveTrend ?? snapshotTrendsByStationId[stationId];
          data['trend'] = (effectiveTrend ?? WaterTrend.stable).name;
          data['has_known_trend'] = effectiveTrend != null;
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
          return stationsByName[key];
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
    WaterLevel? retainedMobileReading;
    if (stationId.trim().isNotEmpty && limit > 0) {
      // The mobile v2 contract intentionally exposes at most 30 days.
      // UI point limits are a separate concern and must never be forwarded as
      // an invalid p_days value (Home currently asks for up to 72 points).
      final requestedDays = limit > 30 ? 30 : limit;

      try {
        final rows = await mobileContractReader.readStationHistory(
          stationId,
          days: requestedDays,
        );
        final readings = _mobileContractHistoryReadings(
          rows,
          stationId: stationId,
          limit: limit,
        );

        if (readings.length >= 2) {
          return WaterHistoryResult(
            status: WaterHistoryResultStatus.success,
            readings: List<WaterLevel>.unmodifiable(readings),
            source: readings.last.source,
            hadProviderError: false,
          );
        }

        if (readings.length == 1) {
          retainedMobileReading = readings.single;
          _logProviderFallback(
            stationName ?? stationId,
            'Water mobile history contract returned one valid observation; '
            'continuing with snapshot and legacy history',
          );
        }

        if (readings.isEmpty) {
          _logProviderFallback(
            stationName ?? stationId,
            'Water mobile history contract returned no valid observations',
          );
        }
      } catch (error, stackTrace) {
        _logFailure('Water mobile history contract', error, stackTrace);
      }
    }

    return _getLegacyHistoryResult(
      stationId,
      stationName: stationName,
      limit: limit,
      prefetchedCurrentReading: prefetchedCurrentReading,
      retainedLiveReading: retainedMobileReading,
    );
  }

  Future<WaterHistoryResult> _getLegacyHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
    WaterLevel? retainedLiveReading,
  }) async {
    final snapshotResult = await getSnapshotHistoryResult(
      stationId,
      limit: limit,
    );
    final failedProviders = <String>[];
    final retainedLiveReadings = <WaterLevel>[
      if (prefetchedCurrentReading != null &&
          _isValidReading(prefetchedCurrentReading))
        prefetchedCurrentReading,
      if (retainedLiveReading != null && _isValidReading(retainedLiveReading))
        retainedLiveReading,
    ];
    List<WaterLevel> liveReadings = retainedLiveReadings;
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
      liveReadings = <WaterLevel>[...selectedReadings, ...retainedLiveReadings];
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

  Future<List<Station>> _stationsFromMobileContract(
    List<Map<String, dynamic>> rows,
  ) async {
    final candidates =
        <
          ({
            int sourceIndex,
            int displayOrder,
            Map<String, dynamic> metadata,
            WaterLevel reading,
          })
        >[];
    final stationRows = <Map<String, dynamic>>[];
    final seenStationIds = <String>{};

    for (var sourceIndex = 0; sourceIndex < rows.length; sourceIndex++) {
      final row = rows[sourceIndex];
      final stationId = row['station_id']?.toString().trim() ?? '';
      final stationName = row['station_name']?.toString().trim() ?? '';
      final riverName = row['river_name']?.toString().trim() ?? '';
      final latitude = _contractDouble(row['latitude']);
      final longitude = _contractDouble(row['longitude']);

      if (stationId.isEmpty ||
          stationName.isEmpty ||
          latitude == null ||
          longitude == null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        continue;
      }

      final reading = _mobileContractReading(row, expectedStationId: stationId);

      if (reading == null ||
          row['is_stale'] == true ||
          !_isWithinDefaultFreshness(reading, DateTime.now().toUtc()) ||
          !seenStationIds.add(stationId)) {
        continue;
      }

      final metadata = <String, dynamic>{
        'id': stationId,
        'name': stationName,
        'river': riverName,
        'latitude': latitude,
        'longitude': longitude,
      };
      stationRows.add(metadata);
      candidates.add((
        sourceIndex: sourceIndex,
        displayOrder: _contractInt(row['display_order']) ?? sourceIndex,
        metadata: metadata,
        reading: reading,
      ));
    }

    if (candidates.isEmpty) return const <Station>[];

    final snapshotTrendsByStationId = await _loadRecentSnapshotTrends(
      stationRows,
    );
    final stations = <({int displayOrder, int sourceIndex, Station station})>[];

    for (final candidate in candidates) {
      final stationId = candidate.metadata['id']!.toString();
      final effectiveTrend = snapshotTrendsByStationId[stationId];
      final station = Station.tryFromJson(<String, dynamic>{
        ...candidate.metadata,
        'level': candidate.reading.value,
        'last_update': candidate.reading.timestamp.toIso8601String(),
        'water_freshness_timestamp': candidate
            .reading
            .effectiveFreshnessTimestamp
            .toIso8601String(),
        'has_water_level': true,
        'water_level_unit': candidate.reading.unit,
        'water_level_source': candidate.reading.source.name,
        'water_measurement_precision':
            candidate.reading.measurementPrecision.name,
        'reported_delta_cm_24h': candidate.reading.reportedDeltaCm24h,
        'water_temperature_c': candidate.reading.waterTemperatureC,
        'trend':
            (candidate.reading.knownTrend ?? effectiveTrend ?? WaterTrend.stable)
                .name,
        'has_known_trend':
            candidate.reading.knownTrend != null || effectiveTrend != null,
      });
      if (station == null) continue;

      stations.add((
        displayOrder: candidate.displayOrder,
        sourceIndex: candidate.sourceIndex,
        station: station,
      ));
    }

    stations.sort((left, right) {
      final byDisplayOrder = left.displayOrder.compareTo(right.displayOrder);
      if (byDisplayOrder != 0) return byDisplayOrder;
      final bySourceOrder = left.sourceIndex.compareTo(right.sourceIndex);
      if (bySourceOrder != 0) return bySourceOrder;
      return left.station.id.compareTo(right.station.id);
    });

    return List<Station>.unmodifiable(stations.map((entry) => entry.station));
  }

  static List<WaterLevel> _mobileContractHistoryReadings(
    List<Map<String, dynamic>> rows, {
    required String stationId,
    required int limit,
  }) {
    final readingsByTimestamp = <int, WaterLevel>{};

    for (final row in rows) {
      final reading = _mobileContractReading(row, expectedStationId: stationId);
      if (reading == null) continue;

      readingsByTimestamp.putIfAbsent(
        reading.timestamp.toUtc().microsecondsSinceEpoch,
        () => reading,
      );
    }

    final chronological = readingsByTimestamp.values.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final effectiveLimit = limit <= 0
        ? 0
        : limit > maxSnapshotHistoryPoints
        ? maxSnapshotHistoryPoints
        : limit;

    if (effectiveLimit == 0) return const <WaterLevel>[];

    final limited = chronological.length <= effectiveLimit
        ? chronological
        : chronological.sublist(chronological.length - effectiveLimit);

    return List<WaterLevel>.unmodifiable(
      _withCalculatedTrends(limited, stationId),
    );
  }

  static WaterLevel? _mobileContractReading(
    Map<String, dynamic> row, {
    required String expectedStationId,
  }) {
    final stationId = row['station_id']?.toString().trim() ?? '';
    final quality = row['quality_status']?.toString().trim().toLowerCase();
    final value = _contractDouble(row['level_cm']);
    final observedAt = DateTime.tryParse(row['observed_at']?.toString() ?? '');
    final freshnessAt = DateTime.tryParse(
      row['freshness_at']?.toString() ?? '',
    );
    final source = _mobileContractSource(row['source_key']);
    final reportedDeltaCm24h = _contractDouble(
      row['reported_delta_cm_24h'],
    );
    final waterTemperatureC = _contractDouble(row['water_temperature_c']);
    final forecast = WaterForecastPoint.listFromJson(row['forecast']);
    final forecastUpdatedAt = DateTime.tryParse(
      row['forecast_updated_at']?.toString() ?? '',
    );
    final reportedTrend = waterTrendFromRealDelta(reportedDeltaCm24h);

    if (stationId != expectedStationId ||
        (quality != 'validated' &&
            quality != 'corrected' &&
            quality != 'raw') ||
        value == null ||
        !value.isFinite ||
        observedAt == null ||
        source == null) {
      return null;
    }

    final reading = WaterLevel(
      stationId: stationId,
      value: value,
      timestamp: observedAt.toUtc(),
      freshnessTimestamp: freshnessAt?.toUtc(),
      measurementPrecision: WaterMeasurementPrecision.parse(
        row['observed_at_precision'],
      ),
      trend: reportedTrend ?? WaterTrend.stable,
      source: source,
      unit: 'cm',
      sourceName: row['source_name']?.toString().trim().isNotEmpty == true
          ? row['source_name'].toString().trim()
          : _sourceLabel(source),
      metricCode: 'water_level',
      measurementDatum:
          row['measurement_datum']?.toString().trim().isNotEmpty == true
          ? row['measurement_datum'].toString().trim()
          : 'source_native',
      historyContract:
          row['history_contract']?.toString().trim().isNotEmpty == true
          ? row['history_contract'].toString().trim()
          : 'canonical_water_level',
      isQualityValid: true,
      measurementResolution: _contractDouble(row['measurement_resolution']),
      hasKnownTrend: reportedTrend != null,
      reportedDeltaCm24h: reportedDeltaCm24h,
      waterTemperatureC: waterTemperatureC,
      forecast: forecast,
      forecastUpdatedAt: forecastUpdatedAt?.toUtc(),
    );

    return _isValidReading(reading) ? reading : null;
  }

  static WaterLevelSource? _mobileContractSource(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'afdj' => WaterLevelSource.afdj,
      'danubehis' || 'danube_his' => WaterLevelSource.danubeHis,
      'danubefis' || 'danube_fis' => WaterLevelSource.danubeFis,
      'inhga' => WaterLevelSource.inhga,
      _ => null,
    };
  }

  static int? _contractInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _contractDouble(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed?.isFinite == true ? parsed : null;
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
          freshnessTimestamp: reading.freshnessTimestamp,
          measurementPrecision: reading.measurementPrecision,
          trend: reading.trend,
          source: reading.source,
          unit: reading.unit,
          sourceName: reading.sourceName,
          hasKnownTrend: reading.hasKnownTrend,
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
        freshnessTimestamp: reading.freshnessTimestamp,
        measurementPrecision: reading.measurementPrecision,
        trend: trend ?? WaterTrend.stable,
        source: reading.source,
        unit: reading.unit,
        sourceName: reading.sourceName,
        hasKnownTrend: reading.hasKnownTrend || trend != null,
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
    }, growable: false);
  }

  static WaterTrend? _trendFromHistory(List<WaterLevel> readings) {
    if (readings.length < 2) return null;
    if (readings.first.hasKnownTrend) return readings.first.trend;
    final difference = readings[0].value - readings[1].value;
    final resolutions = <double>[
      if (readings[0].measurementResolution case final value?
          when value.isFinite && value > 0)
        value,
      if (readings[1].measurementResolution case final value?
          when value.isFinite && value > 0)
        value,
    ];
    return waterTrendFromRealDelta(
      difference,
      measurementResolution: resolutions.isEmpty
          ? null
          : resolutions.reduce((a, b) => a > b ? a : b),
    );
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
      if (!_isWithinDefaultFreshness(candidate, now)) continue;
      if (freshestReading == null) {
        freshestReading = candidate;
        freshestProviderIndex = index;
      }
    }

    if (freshestReading == null) {
      for (var index = 0; index < providers.length; index++) {
        if (providers[index].isEmpty) continue;
        freshestReading = providers[index].first;
        freshestProviderIndex = index;
        break;
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
    final age = now.toUtc().difference(
      reading.effectiveFreshnessTimestamp.toUtc(),
    );
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
    final age = DateTime.now().difference(
      reading.effectiveFreshnessTimestamp.toLocal(),
    );
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
