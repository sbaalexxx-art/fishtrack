import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/afdj_water_provider.dart';
import 'package:fishtrack/repositories/danube_fis_water_provider.dart';
import 'package:fishtrack/repositories/danube_his_water_provider.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'one batch snapshot delta supplies a real station trend fallback',
    () async {
      final now = DateTime.now().toUtc();
      final snapshotReader = _FakeSnapshotReader([
        _snapshotRow(
          deltaCm: -12,
          measuredAt: now.subtract(const Duration(hours: 1)),
        ),
      ]);
      final repository = _repository(
        snapshotReader: snapshotReader,
        danubeFisReadings: [
          _reading(100, now.subtract(const Duration(minutes: 30))),
        ],
      );

      final stations = await repository.getStations();
      final station = stations.singleWhere((item) => item.id == 'afdj-bazias');

      expect(snapshotReader.trendRequestCount, 1);
      expect(station.hasKnownTrend, isTrue);
      expect(station.trend, WaterTrend.falling);
    },
  );

  test('stale snapshot delta never colors a station marker', () async {
    final now = DateTime.now().toUtc();
    final repository = _repository(
      snapshotReader: _FakeSnapshotReader([
        _snapshotRow(
          deltaCm: 8,
          measuredAt: now.subtract(const Duration(hours: 48)),
        ),
      ]),
      danubeFisReadings: [
        _reading(100, now.subtract(const Duration(minutes: 30))),
      ],
    );

    final stations = await repository.getStations();
    final station = stations.singleWhere((item) => item.id == 'afdj-bazias');

    expect(station.hasKnownTrend, isFalse);
  });

  test(
    'compatible live history remains authoritative over snapshot delta',
    () async {
      final now = DateTime.now().toUtc();
      final repository = _repository(
        snapshotReader: _FakeSnapshotReader([
          _snapshotRow(
            deltaCm: -7,
            measuredAt: now.subtract(const Duration(hours: 1)),
          ),
        ]),
        danubeHisReadings: [
          _reading(
            110,
            now.subtract(const Duration(minutes: 30)),
            source: WaterLevelSource.danubeHis,
          ),
          _reading(
            100,
            now.subtract(const Duration(hours: 2)),
            source: WaterLevelSource.danubeHis,
          ),
        ],
      );

      final stations = await repository.getStations();
      final station = stations.singleWhere((item) => item.id == 'afdj-bazias');

      expect(station.hasKnownTrend, isTrue);
      expect(station.trend, WaterTrend.rising);
    },
  );
}

WaterRepository _repository({
  required _FakeSnapshotReader snapshotReader,
  List<WaterLevel> danubeHisReadings = const <WaterLevel>[],
  List<WaterLevel> danubeFisReadings = const <WaterLevel>[],
}) {
  return WaterRepository(
    afdjProvider: const _FakeAfdjProvider(),
    danubeHisProvider: _FakeDanubeHisProvider(danubeHisReadings),
    danubeFisProvider: _FakeDanubeFisProvider(danubeFisReadings),
    stationMetadataReader: const _FakeStationMetadataReader(),
    snapshotReader: snapshotReader,
  );
}

Map<String, Object?> _snapshotRow({
  required int deltaCm,
  required DateTime measuredAt,
}) {
  return <String, Object?>{
    'station_id': 'afdj-bazias',
    'observation_date': measuredAt.toIso8601String().substring(0, 10),
    'daily_delta_cm': deltaCm,
    'delta_source': 'DanubeFIS',
    'delta_measured_at': measuredAt.toIso8601String(),
    'delta_method': 'computed_same_source',
    'quality': 'valid',
  };
}

WaterLevel _reading(
  double value,
  DateTime timestamp, {
  WaterLevelSource source = WaterLevelSource.danubeFis,
}) {
  return WaterLevel(
    stationId: 'afdj-bazias',
    value: value,
    timestamp: timestamp,
    trend: WaterTrend.stable,
    source: source,
    unit: 'cm',
    sourceName: source == WaterLevelSource.danubeHis
        ? 'DanubeHIS'
        : 'DanubeFIS',
  );
}

class _FakeStationMetadataReader implements StationMetadataReader {
  const _FakeStationMetadataReader();

  @override
  Future<List<Map<String, dynamic>>> readStations() async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'afdj-bazias',
        'name': 'Bazias',
        'river': 'Dunarea',
        'latitude': 44.8148,
        'longitude': 21.3895,
        'water_type': 'river',
      },
    ];
  }
}

class _FakeSnapshotReader implements DailyWaterSnapshotReader {
  _FakeSnapshotReader(this.trendRows);

  final List<Map<String, Object?>> trendRows;
  int trendRequestCount = 0;

  @override
  Future<List<Map<String, Object?>>> readRecentStationTrends(
    Iterable<String> stationIds, {
    required DateTime notBefore,
  }) async {
    trendRequestCount++;
    return trendRows;
  }

  @override
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  }) async {
    return const <Map<String, Object?>>[];
  }
}

class _FakeAfdjProvider extends AfdjWaterProvider {
  const _FakeAfdjProvider();

  @override
  Future<Map<String, List<WaterLevel>>> getLevels(
    Iterable<String> stationNames,
  ) async {
    return const <String, List<WaterLevel>>{};
  }
}

class _FakeDanubeHisProvider extends DanubeHisWaterProvider {
  const _FakeDanubeHisProvider(this.readings);

  final List<WaterLevel> readings;

  @override
  Future<Map<String, List<WaterLevel>>> getLevels(
    Iterable<String> stationNames, {
    int limit = 30,
    int? historyDays,
  }) async {
    if (readings.isEmpty) return const <String, List<WaterLevel>>{};
    return <String, List<WaterLevel>>{'bazias': readings};
  }
}

class _FakeDanubeFisProvider extends DanubeFisWaterProvider {
  const _FakeDanubeFisProvider(this.readings);

  final List<WaterLevel> readings;

  @override
  Future<Map<String, List<WaterLevel>>> getLevels(
    Iterable<String> stationNames,
  ) async {
    if (readings.isEmpty) return const <String, List<WaterLevel>>{};
    return <String, List<WaterLevel>>{'bazias': readings};
  }
}
