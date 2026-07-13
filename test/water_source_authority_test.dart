import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WaterService.clearCache);

  test(
    'AFDJ remains AFDJ after WaterLevel Station service round trip',
    () async {
      final reading = _reading(
        value: 535,
        timestamp: _now().subtract(const Duration(hours: 1)),
        source: WaterLevelSource.afdj,
      );
      final service = WaterService(
        repository: _FakeWaterRepository(const <WaterLevel>[]),
      );

      final result = await service.getWaterUiResult(_stationFrom(reading));

      expect(
        WaterLevelSource.parse(reading.source.name),
        WaterLevelSource.afdj,
      );
      expect(result.source, WaterLevelSource.afdj);
      expect(result.latestReading?.source, WaterLevelSource.afdj);
    },
  );

  test(
    'DanubeHIS remains DanubeHIS after WaterLevel Station service round trip',
    () async {
      final reading = _reading(
        value: 535,
        timestamp: _now().subtract(const Duration(hours: 1)),
        source: WaterLevelSource.danubeHis,
      );
      final service = WaterService(
        repository: _FakeWaterRepository(const <WaterLevel>[]),
      );

      final result = await service.getWaterUiResult(_stationFrom(reading));

      expect(
        WaterLevelSource.parse(reading.source.name),
        WaterLevelSource.danubeHis,
      );
      expect(result.source, WaterLevelSource.danubeHis);
      expect(result.latestReading?.source, WaterLevelSource.danubeHis);
    },
  );

  test(
    'DanubeFIS remains DanubeFIS after WaterLevel Station service round trip',
    () async {
      final reading = _reading(
        value: 535,
        timestamp: _now().subtract(const Duration(hours: 1)),
        source: WaterLevelSource.danubeFis,
      );
      final service = WaterService(
        repository: _FakeWaterRepository(const <WaterLevel>[]),
      );

      final result = await service.getWaterUiResult(_stationFrom(reading));

      expect(
        WaterLevelSource.parse(reading.source.name),
        WaterLevelSource.danubeFis,
      );
      expect(result.source, WaterLevelSource.danubeFis);
      expect(result.latestReading?.source, WaterLevelSource.danubeFis);
    },
  );

  test('older official reading wins over newer Manual reading', () async {
    final now = _now();
    final official = _reading(
      value: 535,
      timestamp: now.subtract(const Duration(hours: 24)),
      source: WaterLevelSource.danubeHis,
    );
    final manual = _reading(
      value: 544,
      timestamp: now.subtract(const Duration(hours: 1)),
      source: WaterLevelSource.manualFallback,
    );
    final service = WaterService(repository: _FakeWaterRepository([official]));

    final result = await service.getWaterUiResult(
      _stationFrom(manual),
      historyWindow: const Duration(hours: 25),
    );

    expect(result.latestReading?.value, 535);
    expect(result.source, WaterLevelSource.danubeHis);
    expect(result.status, WaterUiStatus.insufficientHistory);
  });

  test('newest reading wins when both readings are official', () async {
    final now = _now();
    final afdj = _reading(
      value: 535,
      timestamp: now.subtract(const Duration(hours: 2)),
      source: WaterLevelSource.afdj,
    );
    final danubeHis = _reading(
      value: 540,
      timestamp: now.subtract(const Duration(hours: 1)),
      source: WaterLevelSource.danubeHis,
    );
    final service = WaterService(repository: _FakeWaterRepository([danubeHis]));

    final result = await service.getWaterUiResult(_stationFrom(afdj));

    expect(result.latestReading?.value, 540);
    expect(result.source, WaterLevelSource.danubeHis);
  });

  test(
    'Manual remains available and unverified without official data',
    () async {
      final manual = _reading(
        value: 544,
        timestamp: _now().subtract(const Duration(hours: 1)),
        source: WaterLevelSource.manualFallback,
      );
      final service = WaterService(
        repository: _FakeWaterRepository(const <WaterLevel>[]),
      );

      final result = await service.getWaterUiResult(_stationFrom(manual));

      expect(result.latestReading?.value, 544);
      expect(result.source, WaterLevelSource.manualFallback);
      expect(result.status, WaterUiStatus.insufficientHistory);
    },
  );

  test(
    'history from another provider is not associated with current',
    () async {
      final now = _now();
      final current = _reading(
        value: 540,
        timestamp: now.subtract(const Duration(minutes: 30)),
        source: WaterLevelSource.afdj,
        trend: WaterTrend.falling,
        hasKnownTrend: true,
      );
      final service = WaterService(
        repository: _FakeWaterRepository([
          _reading(
            value: 530,
            timestamp: now.subtract(const Duration(hours: 2)),
            source: WaterLevelSource.danubeHis,
          ),
          _reading(
            value: 535,
            timestamp: now.subtract(const Duration(hours: 1)),
            source: WaterLevelSource.danubeHis,
          ),
        ]),
      );

      final result = await service.getWaterUiResult(_stationFrom(current));

      expect(result.source, WaterLevelSource.afdj);
      expect(result.history, isEmpty);
      expect(result.latestReading?.hasKnownTrend, isFalse);
      expect(result.status, WaterUiStatus.insufficientHistory);
    },
  );

  test('two same-source points produce compatible history', () async {
    final now = _now();
    final current = _reading(
      value: 540,
      timestamp: now.subtract(const Duration(minutes: 30)),
      source: WaterLevelSource.afdj,
    );
    final service = WaterService(
      repository: _FakeWaterRepository([
        _reading(
          value: 530,
          timestamp: now.subtract(const Duration(hours: 2)),
          source: WaterLevelSource.afdj,
        ),
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );

    final result = await service.getWaterUiResult(_stationFrom(current));

    expect(result.history, hasLength(2));
    expect(
      result.history.every(
        (reading) => reading.source == WaterLevelSource.afdj,
      ),
      isTrue,
    );
    expect(result.latestReading?.trend, WaterTrend.rising);
    expect(result.latestReading?.hasKnownTrend, isTrue);
    expect(result.status, WaterUiStatus.availableHistory);
  });

  test('memoized repeat preserves source value status and trend', () async {
    final now = _now();
    final current = _reading(
      value: 540,
      timestamp: now.subtract(const Duration(minutes: 30)),
      source: WaterLevelSource.danubeHis,
    );
    final repository = _FakeWaterRepository([
      _reading(
        value: 530,
        timestamp: now.subtract(const Duration(hours: 2)),
        source: WaterLevelSource.danubeHis,
      ),
      _reading(
        value: 535,
        timestamp: now.subtract(const Duration(hours: 1)),
        source: WaterLevelSource.danubeHis,
      ),
    ]);
    final service = WaterService(repository: repository);
    final station = _stationFrom(current);

    final first = await service.getWaterUiResult(station);
    final second = await service.getWaterUiResult(station);

    expect(repository.historyRequestCount, 1);
    expect(second.source, first.source);
    expect(second.latestReading?.value, first.latestReading?.value);
    expect(second.status, first.status);
    expect(second.latestReading?.trend, first.latestReading?.trend);
    expect(
      second.latestReading?.hasKnownTrend,
      first.latestReading?.hasKnownTrend,
    );
  });

  test('INHGA official reading wins over newer Manual reading', () async {
    final now = _now();
    final inhga = _reading(
      value: 535,
      timestamp: now.subtract(const Duration(hours: 24)),
      source: WaterLevelSource.inhga,
    );
    final manual = _reading(
      value: 544,
      timestamp: now.subtract(const Duration(hours: 1)),
      source: WaterLevelSource.manualFallback,
    );
    final service = WaterService(repository: _FakeWaterRepository([inhga]));

    final result = await service.getWaterUiResult(
      _stationFrom(manual),
      historyWindow: const Duration(hours: 25),
    );

    expect(result.latestReading?.value, 535);
    expect(result.source, WaterLevelSource.inhga);
  });
}

class _FakeWaterRepository extends WaterRepository {
  _FakeWaterRepository(this.readings);

  final List<WaterLevel> readings;
  int historyRequestCount = 0;

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
  }) async {
    historyRequestCount++;
    final limited = readings.take(limit).toList(growable: false);
    return WaterHistoryResult(
      status: limited.length >= 2
          ? WaterHistoryResultStatus.success
          : limited.isEmpty
          ? WaterHistoryResultStatus.unavailable
          : WaterHistoryResultStatus.insufficientHistory,
      readings: limited,
      source: limited.isEmpty ? null : limited.last.source,
      hadProviderError: false,
    );
  }
}

DateTime _now() => DateTime.now().toUtc();

WaterLevel _reading({
  required double value,
  required DateTime timestamp,
  required WaterLevelSource source,
  WaterTrend trend = WaterTrend.stable,
  bool hasKnownTrend = false,
}) {
  return WaterLevel(
    stationId: 'bazias',
    value: value,
    timestamp: timestamp,
    trend: trend,
    source: source,
    sourceName: source.name,
    hasKnownTrend: hasKnownTrend,
  );
}

Station _stationFrom(WaterLevel reading) {
  return Station(
    id: reading.stationId,
    name: 'Bazias',
    river: 'Dunarea',
    level: reading.value,
    trend: reading.trend,
    latitude: 44.8167,
    longitude: 21.3833,
    lastUpdate: reading.timestamp,
    hasWaterLevel: true,
    waterLevelUnit: reading.unit,
    waterLevelSource: reading.source.name,
    hasKnownTrend: reading.hasKnownTrend,
  );
}
