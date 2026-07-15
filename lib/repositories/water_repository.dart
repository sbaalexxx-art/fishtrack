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
  });

  final AfdjWaterProvider afdjProvider;
  final DanubeHisWaterProvider danubeHisProvider;
  final DanubeFisWaterProvider danubeFisProvider;

  static const defaultFreshnessThreshold = Duration(hours: 36);

  static const officialAfdjStationOrder = <String>[
    'Bazias',
    'Moldova Veche',
    'Drencova',
    'Orsova',
    'Drobeta Turnu Severin',
    'Gruia',
    'Cetate',
    'Calafat',
    'Rast',
    'Bechet',
    'Corabia',
    'Turnu Magurele',
    'Zimnicea',
    'Giurgiu',
    'Oltenita',
    'Calarasi',
    'Cernavoda',
    'Harsova',
    'Braila',
    'Galati',
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

  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) async {
    final failedProviders = <String>[];
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
      if (selectedReadings.isNotEmpty) {
        final readings = _chronologicalValidReadings(
          _withCalculatedTrends(selectedReadings, stationId),
        );
        if (readings.isNotEmpty) {
          final status = readings.length >= 2
              ? WaterHistoryResultStatus.success
              : WaterHistoryResultStatus.insufficientHistory;
          return WaterHistoryResult(
            status: status,
            readings: List<WaterLevel>.unmodifiable(readings),
            source: readings.last.source,
            hadProviderError: failedProviders.isNotEmpty,
            safeDiagnosticMessage: _safeProviderDiagnostic(failedProviders),
          );
        }
      }
    }
    _logProviderFallback(stationName ?? stationId, 'no provider history');
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

  static List<WaterLevel> _withCalculatedTrends(
    List<WaterLevel> readings,
    String stationId,
  ) {
    return List.generate(readings.length, (index) {
      final reading = readings[index];
      final trend = reading.hasKnownTrend
          ? reading.trend
          : index + 1 < readings.length
          ? _trendFromHistory([reading, readings[index + 1]])
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

  static List<WaterLevel> _chronologicalValidReadings(
    List<WaterLevel> readings,
  ) {
    final valid = readings.where(_isValidReading).toList(growable: false);
    valid.sort((a, b) {
      final timestampComparison = a.timestamp.compareTo(b.timestamp);
      if (timestampComparison != 0) return timestampComparison;
      final sourceComparison = a.source.index.compareTo(b.source.index);
      if (sourceComparison != 0) return sourceComparison;
      final stationComparison = a.stationId.compareTo(b.stationId);
      if (stationComparison != 0) return stationComparison;
      return a.value.compareTo(b.value);
    });
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
        ...danubeHis
            .where(
              (reading) => reading.timestamp.isBefore(afdj.first.timestamp),
            )
            .take(13),
      ];
    }
    if (danubeHis.isNotEmpty) {
      _logAfdjNotSelected(stationName, 'no valid AFDJ reading matched');
      _logProviderUsed(stationName, danubeHis.first, 'AFDJ unavailable');
      return danubeHis.take(14).toList(growable: false);
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
