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

class WaterRepository implements OfficialWaterDataSource {
  const WaterRepository({
    this.afdjProvider = const AfdjWaterProvider(),
    this.danubeHisProvider = const DanubeHisWaterProvider(),
    this.danubeFisProvider = const DanubeFisWaterProvider(),
  });

  final AfdjWaterProvider afdjProvider;
  final DanubeHisWaterProvider danubeHisProvider;
  final DanubeFisWaterProvider danubeFisProvider;

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
          final providerReadings = _selectProviderReadings(
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
            data['water_level_source'] = latest.sourceName;
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
  }) async {
    if (stationName != null && stationName.trim().isNotEmpty) {
      final normalized = DanubeHisWaterProvider.normalizedName(stationName);
      List<WaterLevel> afdjReadings = const [];
      List<WaterLevel> hisReadings = const [];
      List<WaterLevel> fisReadings = const [];
      try {
        final result = await afdjProvider.getLevels([stationName]);
        afdjReadings = result[normalized] ?? const [];
      } on Exception catch (error, stackTrace) {
        _logFailure('AFDJ history', error, stackTrace);
        _logAfdjNotSelected(stationName, _providerFailureReason(error));
      }
      try {
        final result = await danubeHisProvider.getLevels([
          stationName,
        ], limit: limit);
        hisReadings = result[normalized] ?? const [];
      } on Exception catch (error, stackTrace) {
        _logFailure('DanubeHIS history', error, stackTrace);
      }
      try {
        final result = await danubeFisProvider.getLevels([stationName]);
        fisReadings = result[normalized] ?? const [];
      } on Exception catch (error, stackTrace) {
        _logFailure('DanubeFIS history', error, stackTrace);
      }
      final readings = _selectProviderReadings(
        stationName,
        afdjReadings,
        hisReadings,
        fisReadings,
      );
      if (readings.isNotEmpty) {
        return _withCalculatedTrends(readings, stationId);
      }
    }
    _logProviderFallback(stationName ?? stationId, 'no provider history');
    return const [];
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
