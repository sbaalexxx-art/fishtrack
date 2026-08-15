import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WaterService.clearCache);

  test('AFDJ date-only measurement uses source freshness end to end', () async {
    final now = DateTime.now().toUtc();
    final measurement = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 2));
    final freshness = now.subtract(const Duration(minutes: 12));
    final row = _canonicalLatestRows().first
      ..['observed_at'] = measurement.toIso8601String()
      ..['observed_at_precision'] = 'date'
      ..['source_changed_at'] = freshness.toIso8601String()
      ..['freshness_at'] = freshness.toIso8601String()
      ..['freshness_minutes'] = 12
      ..['is_stale'] = false;
    final repository = WaterRepository(
      mobileContractReader: _FakeWaterMobileContractReader(latestRows: [row]),
      snapshotReader: _FakeSnapshotReader(const []),
    );

    final station = (await repository.getStations()).single;
    final result = await WaterService(
      repository: repository,
    ).getWaterUiResult(station);

    expect(station.lastUpdate, measurement);
    expect(station.waterFreshnessTimestamp, freshness);
    expect(result.measurementTimestamp, measurement);
    expect(result.effectiveFreshnessTimestamp, freshness);
    expect(
      result.latestReading?.measurementPrecision,
      WaterMeasurementPrecision.date,
    );
    expect(result.dataAge, lessThan(const Duration(hours: 1)));
    expect(result.isStale, isFalse);
  });

  test(
    'AFDJ exact observation preserves exact measurement semantics',
    () async {
      final row = _canonicalLatestRows().first;
      final repository = WaterRepository(
        mobileContractReader: _FakeWaterMobileContractReader(latestRows: [row]),
        snapshotReader: _FakeSnapshotReader(const []),
      );

      final station = (await repository.getStations()).single;
      final result = await WaterService(
        repository: repository,
      ).getWaterUiResult(station);

      expect(
        result.latestReading?.measurementPrecision,
        WaterMeasurementPrecision.exact,
      );
      expect(
        result.latestReading?.effectiveFreshnessTimestamp,
        result.latestReading?.timestamp,
      );
    },
  );

  test('DanubeHIS relative latest remains relative, never exact', () async {
    final now = DateTime.now().toUtc();
    final row = _canonicalLatestRows().first
      ..['source_key'] = 'DanubeHIS'
      ..['source_name'] = 'DanubeHIS'
      ..['observed_at'] = now
          .subtract(const Duration(minutes: 25))
          .toIso8601String()
      ..['observed_at_precision'] = 'relative'
      ..['freshness_at'] = now
          .subtract(const Duration(minutes: 25))
          .toIso8601String();
    final repository = WaterRepository(
      mobileContractReader: _FakeWaterMobileContractReader(latestRows: [row]),
      snapshotReader: _FakeSnapshotReader(const []),
    );

    final station = (await repository.getStations()).single;
    final result = await WaterService(
      repository: repository,
    ).getWaterUiResult(station);

    expect(result.source, WaterLevelSource.danubeHis);
    expect(
      result.latestReading?.measurementPrecision,
      WaterMeasurementPrecision.relative,
    );
  });

  test(
    'mobile latest contract builds all 23 canonical Danube stations',
    () async {
      final mobileReader = _FakeWaterMobileContractReader(
        latestRows: _canonicalLatestRows(),
      );

      final repository = WaterRepository(
        mobileContractReader: mobileReader,
        snapshotReader: _FakeSnapshotReader(const []),
      );

      final stations = await repository.getStations();

      expect(mobileReader.latestCalls, 1);
      expect(stations, hasLength(23));
      expect(stations.first.id, 'bazias');
      expect(stations.first.name, 'Baziaș');
      expect(stations.first.level, 500);
      expect(stations.first.waterLevelSource, 'afdj');
      expect(stations.first.hasWaterLevel, isTrue);
      expect(stations.last.id, 'sulina');
      expect(stations.last.name, 'Sulina');
      expect(stations.every((station) => station.hasWaterLevel), isTrue);
    },
  );

  test('mobile history preserves multiple sources and calculates trends only '
      'within the same source', () async {
    final now = DateTime.now().toUtc();
    final mobileReader = _FakeWaterMobileContractReader(
      historyRows: [
        _historyRow(
          stationId: 'station-a',
          level: 100,
          observedAt: now.subtract(const Duration(days: 3)),
          sourceKey: 'AFDJ',
          sourceName: 'AFDJ',
        ),
        _historyRow(
          stationId: 'station-a',
          level: 110,
          observedAt: now.subtract(const Duration(days: 2)),
          sourceKey: 'AFDJ',
          sourceName: 'AFDJ',
        ),
        _historyRow(
          stationId: 'station-a',
          level: 90,
          observedAt: now.subtract(const Duration(days: 1)),
          sourceKey: 'DanubeHIS',
          sourceName: 'DanubeHIS',
        ),
      ],
    );

    final repository = WaterRepository(
      mobileContractReader: mobileReader,
      snapshotReader: _FakeSnapshotReader(const []),
    );

    final result = await repository.getHistoryResult('station-a', limit: 30);

    expect(mobileReader.historyStationIds, ['station-a']);
    expect(mobileReader.historyDays, [30]);
    expect(result.status, WaterHistoryResultStatus.success);
    expect(result.readings.map((reading) => reading.value), [100, 110, 90]);

    expect(result.readings[0].source, WaterLevelSource.afdj);
    expect(result.readings[0].hasKnownTrend, isFalse);

    expect(result.readings[1].source, WaterLevelSource.afdj);
    expect(result.readings[1].trend, WaterTrend.rising);
    expect(result.readings[1].hasKnownTrend, isTrue);

    expect(result.readings[2].source, WaterLevelSource.danubeHis);
    expect(result.readings[2].hasKnownTrend, isFalse);
    expect(result.source, WaterLevelSource.danubeHis);
    expect(result.hadProviderError, isFalse);
  });

  test(
    'history ordering and deduplication use measurement timestamp',
    () async {
      final now = DateTime.now().toUtc();
      final olderMeasurement = now.subtract(const Duration(days: 2));
      final newerMeasurement = now.subtract(const Duration(days: 1));
      final mobileReader = _FakeWaterMobileContractReader(
        historyRows: [
          _historyRow(
            stationId: 'station-a',
            level: 100,
            observedAt: olderMeasurement,
            freshnessAt: now.subtract(const Duration(minutes: 5)),
            sourceKey: 'AFDJ',
            sourceName: 'AFDJ',
          ),
          _historyRow(
            stationId: 'station-a',
            level: 110,
            observedAt: newerMeasurement,
            freshnessAt: now.subtract(const Duration(hours: 4)),
            sourceKey: 'AFDJ',
            sourceName: 'AFDJ',
          ),
        ],
      );
      final repository = WaterRepository(
        mobileContractReader: mobileReader,
        snapshotReader: _FakeSnapshotReader(const []),
      );

      final result = await repository.getHistoryResult('station-a', limit: 30);

      expect(result.readings.map((reading) => reading.timestamp), [
        olderMeasurement,
        newerMeasurement,
      ]);
      expect(result.readings.map((reading) => reading.value), [100, 110]);
    },
  );

  test(
    'one mobile observation continues into real snapshot history merge',
    () async {
      final now = DateTime.now().toUtc();
      final snapshotOlder = now.subtract(const Duration(days: 2));
      final snapshotNewer = now.subtract(const Duration(days: 1));
      final mobileCurrent = now.subtract(const Duration(hours: 1));
      final mobileReader = _FakeWaterMobileContractReader(
        historyRows: [
          _historyRow(
            stationId: 'station-a',
            level: -105,
            observedAt: mobileCurrent,
            sourceKey: 'AFDJ',
            sourceName: 'AFDJ',
          ),
        ],
      );
      final snapshotReader = _FakeSnapshotReader([
        _snapshotRow(
          stationId: 'station-a',
          observationDate: _dateOnly(snapshotOlder),
          level: -118,
          measuredAt: snapshotOlder,
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: _dateOnly(snapshotNewer),
          level: -111,
          measuredAt: snapshotNewer,
        ),
      ]);
      final repository = WaterRepository(
        mobileContractReader: mobileReader,
        snapshotReader: snapshotReader,
      );

      final result = await repository.getHistoryResult('station-a', limit: 30);

      expect(snapshotReader.stationIds, ['station-a']);
      expect(result.status, WaterHistoryResultStatus.success);
      expect(result.readings.map((reading) => reading.value), [
        -118,
        -111,
        -105,
      ]);
      expect(result.readings.map((reading) => reading.timestamp), [
        snapshotOlder,
        snapshotNewer,
        mobileCurrent,
      ]);
      expect(result.readings, hasLength(3));
      expect(result.readings.last.value, -105);
      expect(result.readings.last.timestamp, mobileCurrent);
      expect(result.readings.last.source, WaterLevelSource.afdj);
    },
  );

  test('two mobile observations keep the canonical fast path', () async {
    final now = DateTime.now().toUtc();
    final older = now.subtract(const Duration(days: 1));
    final current = now.subtract(const Duration(hours: 1));
    final mobileReader = _FakeWaterMobileContractReader(
      historyRows: [
        _historyRow(
          stationId: 'station-a',
          level: 100,
          observedAt: older,
          sourceKey: 'AFDJ',
          sourceName: 'AFDJ',
        ),
        _historyRow(
          stationId: 'station-a',
          level: 104,
          observedAt: current,
          sourceKey: 'AFDJ',
          sourceName: 'AFDJ',
        ),
      ],
    );
    final snapshotReader = _FakeSnapshotReader([
      _snapshotRow(
        stationId: 'station-a',
        observationDate: _dateOnly(now.subtract(const Duration(days: 2))),
        level: 90,
        measuredAt: now.subtract(const Duration(days: 2)),
      ),
    ]);
    final repository = WaterRepository(
      mobileContractReader: mobileReader,
      snapshotReader: snapshotReader,
    );

    final result = await repository.getHistoryResult('station-a', limit: 30);

    expect(snapshotReader.stationIds, isEmpty);
    expect(result.status, WaterHistoryResultStatus.success);
    expect(result.readings.map((reading) => reading.value), [100, 104]);
    expect(result.readings.map((reading) => reading.timestamp), [
      older,
      current,
    ]);
    expect(result.readings.last.timestamp, current);
  });

  test(
    'mobile history failure falls back to preserved snapshot history',
    () async {
      final now = DateTime.now().toUtc();
      final mobileReader = _FakeWaterMobileContractReader(failHistory: true);
      final snapshotReader = _FakeSnapshotReader([
        _snapshotRow(
          stationId: 'station-a',
          observationDate: _dateOnly(now.subtract(const Duration(days: 2))),
          level: 210,
          measuredAt: now.subtract(const Duration(days: 2)),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: _dateOnly(now.subtract(const Duration(days: 1))),
          level: 218,
          measuredAt: now.subtract(const Duration(days: 1)),
        ),
      ]);

      final repository = WaterRepository(
        mobileContractReader: mobileReader,
        snapshotReader: snapshotReader,
      );

      final result = await repository.getHistoryResult('station-a', limit: 30);

      expect(mobileReader.historyCalls, 1);
      expect(snapshotReader.stationIds, ['station-a']);
      expect(result.status, WaterHistoryResultStatus.success);
      expect(result.readings.map((reading) => reading.value), [210, 218]);
      expect(result.readings.last.trend, WaterTrend.rising);
      expect(result.readings.last.hasKnownTrend, isTrue);
      expect(result.hadProviderError, isFalse);
    },
  );
}

class _FakeWaterMobileContractReader implements WaterMobileContractReader {
  _FakeWaterMobileContractReader({
    this.latestRows = const [],
    this.historyRows = const [],
    this.failHistory = false,
  });

  final List<Map<String, dynamic>> latestRows;
  final List<Map<String, dynamic>> historyRows;
  final bool failHistory;

  int latestCalls = 0;
  int historyCalls = 0;
  final List<String> historyStationIds = [];
  final List<int> historyDays = [];

  @override
  Future<List<Map<String, dynamic>>> readLatestStations({
    String? stationId,
  }) async {
    latestCalls++;
    return latestRows;
  }

  @override
  Future<List<Map<String, dynamic>>> readStationHistory(
    String stationId, {
    required int days,
  }) async {
    historyCalls++;
    historyStationIds.add(stationId);
    historyDays.add(days);

    if (failHistory) {
      throw StateError('Simulated history-contract failure');
    }

    return historyRows;
  }
}

class _FakeSnapshotReader implements DailyWaterSnapshotReader {
  _FakeSnapshotReader(this.rows);

  final List<Map<String, Object?>> rows;
  final List<String> stationIds = [];
  final List<int> limits = [];

  @override
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  }) async {
    stationIds.add(stationId);
    limits.add(limit);
    return rows;
  }

  @override
  Future<List<Map<String, Object?>>> readRecentStationTrends(
    Iterable<String> stationIds, {
    required DateTime notBefore,
  }) async {
    return const [];
  }
}

List<Map<String, dynamic>> _canonicalLatestRows() {
  final observedAt = DateTime.now().toUtc().subtract(
    const Duration(minutes: 30),
  );

  const stations = <MapEntry<String, String>>[
    MapEntry('bazias', 'Baziaș'),
    MapEntry('moldova_veche', 'Moldova Veche'),
    MapEntry('afdj-drencova', 'Drencova'),
    MapEntry('orsova', 'Orșova'),
    MapEntry('drobeta_turnu_severin', 'Drobeta Turnu Severin'),
    MapEntry('afdj-gruia', 'Gruia'),
    MapEntry('afdj-cetate', 'Cetate'),
    MapEntry('calafat', 'Calafat'),
    MapEntry('afdj-rast', 'Rast'),
    MapEntry('bechet', 'Bechet'),
    MapEntry('corabia', 'Corabia'),
    MapEntry('turnu_magurele', 'Turnu Măgurele'),
    MapEntry('zimnicea', 'Zimnicea'),
    MapEntry('giurgiu', 'Giurgiu'),
    MapEntry('oltenita', 'Oltenița'),
    MapEntry('calarasi', 'Călărași'),
    MapEntry('cernavoda', 'Cernavodă'),
    MapEntry('harsova', 'Hârșova'),
    MapEntry('braila', 'Brăila'),
    MapEntry('galati', 'Galați'),
    MapEntry('isaccea', 'Isaccea'),
    MapEntry('tulcea', 'Tulcea'),
    MapEntry('sulina', 'Sulina'),
  ];

  return List.generate(stations.length, (index) {
    final station = stations[index];

    return <String, dynamic>{
      'station_id': station.key,
      'station_name': station.value,
      'river_name': 'Dunărea',
      'latitude': 44.0 + index / 100,
      'longitude': 21.0 + index / 100,
      'display_order': index + 1,
      'level_cm': 500 + index,
      'observed_at': observedAt.toIso8601String(),
      'observed_at_precision': 'exact',
      'source_changed_at': null,
      'freshness_at': observedAt.toIso8601String(),
      'source_key': 'AFDJ',
      'source_name': 'AFDJ',
      'quality_status': 'validated',
      'confidence': 'high',
      'fetched_at': observedAt
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'freshness_minutes': 30,
      'is_stale': false,
    };
  });
}

Map<String, dynamic> _historyRow({
  required String stationId,
  required double level,
  required DateTime observedAt,
  DateTime? freshnessAt,
  required String sourceKey,
  required String sourceName,
}) {
  return <String, dynamic>{
    'station_id': stationId,
    'level_cm': level,
    'observed_at': observedAt.toUtc().toIso8601String(),
    'observed_at_precision': 'exact',
    'freshness_at': freshnessAt?.toUtc().toIso8601String(),
    'source_key': sourceKey,
    'source_name': sourceName,
    'quality_status': 'validated',
    'confidence': 'high',
    'fetched_at': observedAt
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
    'data_origin': 'operational',
  };
}

Map<String, Object?> _snapshotRow({
  required String stationId,
  required String observationDate,
  required double level,
  required DateTime measuredAt,
}) {
  return <String, Object?>{
    'station_id': stationId,
    'observation_date': observationDate,
    'level_cm': level,
    'level_source': 'DanubeFIS',
    'level_measured_at': measuredAt.toUtc().toIso8601String(),
    'quality': 'valid',
  };
}

String _dateOnly(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);
