import 'dart:async';

import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/widgets/home_premium/water_level_card.dart'
    show
        formatWaterCardDelta,
        shouldShowWaterHistoryChart,
        shouldShowWaterLiveBadge,
        waterCardTrendColor;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    WaterService.clearCache();
    WaterService.resetStationSelectionForTest();
    SharedPreferences.setMockInitialValues({});
  });

  test('Water card formats real deltas without inventing zero', () {
    expect(formatWaterCardDelta(41, 'cm'), '+41 cm');
    expect(formatWaterCardDelta(-12, 'cm'), '-12 cm');
    expect(formatWaterCardDelta(0, 'cm'), '0 cm');
    expect(formatWaterCardDelta(null, 'cm'), '—');
    expect(formatWaterCardDelta(.4, 'cm'), '+0.4 cm');
  });

  test('Water card maps each real trend to its official color', () {
    expect(waterCardTrendColor(WaterTrend.rising), const Color(0xFF2196F3));
    expect(waterCardTrendColor(WaterTrend.stable), const Color(0xFF43A047));
    expect(waterCardTrendColor(WaterTrend.falling), const Color(0xFFE53935));
    expect(waterCardTrendColor(null), const Color(0xFF9AA7B2));
  });

  test('Water card does not draw a chart without two real points', () {
    final reading = _reading(
      stationId: 'station-a',
      value: 500,
      timestamp: DateTime.utc(2026, 7, 16),
      source: WaterLevelSource.danubeFis,
    );

    expect(shouldShowWaterHistoryChart(const <WaterLevel>[]), isFalse);
    expect(shouldShowWaterHistoryChart([reading]), isFalse);
    expect(shouldShowWaterHistoryChart([reading, reading]), isTrue);
  });

  test(
    'automatic candidates choose the nearest eligible canonical station',
    () {
      final candidates = WaterService.rankHomeCandidates(
        [
          _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
          _homeStation('afdj-tulcea', 'Tulcea', 45.1786, 28.8059),
          _homeStation('afdj-galati', 'Galati', 45.4353, 28.0080),
        ],
        latitude: 45.17,
        longitude: 28.81,
      );

      expect(candidates.first.id, 'afdj-tulcea');
    },
  );

  test('automatic fallback does not pin Bazias merely because it is first', () {
    final candidates = WaterService.rankHomeCandidates([
      _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
      _homeStation('afdj-moldova-veche', 'Moldova Veche', 44.7383, 21.6333),
    ]);

    expect(candidates.first.id, 'afdj-moldova-veche');
  });

  test('automatic candidates exclude invalid and noncanonical stations', () {
    final candidates = WaterService.rankHomeCandidates([
      _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
      _homeStation('afdj-chilia', 'Chilia Veche', 45.4167, 29.3),
      _homeStation(
        'afdj-tulcea',
        'Tulcea',
        45.1786,
        28.8059,
        hasReading: false,
      ),
    ]);

    expect(candidates.map((station) => station.id), ['afdj-bazias']);
  });

  test('automatic candidates are capped at five stations', () {
    final candidates = WaterService.rankHomeCandidates([
      _homeStation('afdj-bazias', 'Bazias', 44.8167, 21.3833),
      _homeStation('afdj-moldova', 'Moldova Veche', 44.7383, 21.6333),
      _homeStation('afdj-drencova', 'Drencova', 44.6377, 21.9723),
      _homeStation('afdj-orsova', 'Orsova', 44.725, 22.396),
      _homeStation('afdj-drobeta', 'Drobeta Turnu Severin', 44.631, 22.656),
      _homeStation('afdj-gruia', 'Gruia', 44.2665, 22.7046),
    ]);

    expect(candidates, hasLength(5));
  });

  test(
    'manual selection persists pinned mode and automatic clears it',
    () async {
      final service = WaterService();
      final station = _homeStation('afdj-tulcea', 'Tulcea', 45.1786, 28.8059);

      service.selectStation(station);
      await Future<void>.delayed(Duration.zero);
      final preferences = await SharedPreferences.getInstance();
      expect(service.selectionMode, WaterStationSelectionMode.pinned);
      expect(
        preferences.getString('water_home_station_selection_mode'),
        'pinned',
      );
      expect(preferences.getString('water_home_pinned_station_id'), station.id);

      await service.setAutomatic();
      expect(service.selectionMode, WaterStationSelectionMode.automatic);
      expect(
        preferences.getString('water_home_station_selection_mode'),
        'automatic',
      );
      expect(preferences.containsKey('water_home_pinned_station_id'), isFalse);
    },
  );

  test('station metadata preserves missing dynamic Water fields', () {
    final station = Station.tryFromJson({
      'id': 'afdj-drencova',
      'name': 'Drencova',
      'river': 'Dunărea',
      'latitude': 44.6377707,
      'longitude': 21.9723364,
      'level': null,
      'trend': null,
      'last_update': null,
    });

    expect(station, isNotNull);
    expect(station!.persistedLevel, isNull);
    expect(station.persistedTrend, isNull);
    expect(station.persistedLastUpdate, isNull);
    expect(station.level.isNaN, isTrue);
    expect(station.hasWaterLevel, isFalse);
    expect(station.hasKnownTrend, isFalse);
    expect(station.trendText, 'Unknown');
    expect(station.lastUpdate.millisecondsSinceEpoch, 0);
  });

  test('complete station metadata remains compatible', () {
    final observedAt = DateTime.utc(2026, 7, 16, 9, 30);
    final station = Station.tryFromJson({
      'id': 'afdj-tulcea',
      'name': 'Tulcea',
      'river': 'Dunărea',
      'latitude': 45.1786,
      'longitude': 28.8059,
      'level': 214,
      'trend': 'falling',
      'last_update': observedAt.toIso8601String(),
      'has_water_level': true,
      'has_known_trend': true,
    });

    expect(station, isNotNull);
    expect(station!.persistedLevel, 214);
    expect(station.persistedTrend, WaterTrend.falling);
    expect(station.persistedLastUpdate, observedAt);
    expect(station.level, 214);
    expect(station.trend, WaterTrend.falling);
    expect(station.lastUpdate, observedAt);
    expect(station.hasWaterLevel, isTrue);
    expect(station.hasKnownTrend, isTrue);
  });

  test(
    'daily snapshots keep real chronological readings once per day',
    () async {
      final reader = _FakeSnapshotReader([
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-14',
          level: 500,
          measuredAt: DateTime.utc(2026, 7, 14, 8),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-15',
          level: 505,
          measuredAt: DateTime.utc(2026, 7, 15, 8),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-15',
          level: 512,
          measuredAt: DateTime.utc(2026, 7, 15, 12),
        ),
        _snapshotRow(
          stationId: 'station-b',
          observationDate: '2026-07-16',
          level: 999,
          measuredAt: DateTime.utc(2026, 7, 16),
        ),
        _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-07-16',
          level: null,
          measuredAt: DateTime.utc(2026, 7, 16),
        ),
      ]);
      final result = await WaterRepository(
        snapshotReader: reader,
      ).getSnapshotHistoryResult('station-a', limit: 30);

      expect(reader.stationIds, ['station-a']);
      expect(reader.limits, [30]);
      expect(result.status, WaterHistoryResultStatus.success);
      expect(result.readings.map((reading) => reading.value), [500, 512]);
      expect(result.readings.last.trend, WaterTrend.rising);
      expect(result.readings.last.hasKnownTrend, isTrue);
      expect(
        result.readings.every((reading) => reading.stationId == 'station-a'),
        isTrue,
      );
    },
  );

  test(
    'daily snapshot history caps the requested series at thirty points',
    () async {
      final rows = List.generate(
        35,
        (index) => _snapshotRow(
          stationId: 'station-a',
          observationDate: '2026-06-${(index + 1).toString().padLeft(2, '0')}',
          level: index.toDouble(),
          measuredAt: DateTime.utc(2026, 6, index + 1),
        ),
      );
      final result = await WaterRepository(
        snapshotReader: _FakeSnapshotReader(rows),
      ).getSnapshotHistoryResult('station-a', limit: 99);

      expect(result.readings, hasLength(30));
      expect(result.readings.first.value, 5);
      expect(result.readings.last.value, 34);
    },
  );

  test('snapshot history exposes a positive delta and real interval', () async {
    final result = await WaterService(
      repository: _StaticHistoryRepository(
        _history([
          _reading(
            stationId: 'station-a',
            value: 500,
            timestamp: DateTime.utc(2026, 7, 10),
            source: WaterLevelSource.danubeFis,
          ),
          _reading(
            stationId: 'station-a',
            value: 512,
            timestamp: DateTime.utc(2026, 7, 13),
            source: WaterLevelSource.danubeFis,
          ),
        ]),
      ),
    ).getWaterUiResult(_stationWithoutReading());

    expect(result.deltaCm, 12);
    expect(result.trend, WaterTrend.rising);
    expect(result.comparisonDuration, const Duration(days: 3));
    expect(result.hasEnoughHistory, isTrue);
  });

  test(
    'snapshot history exposes negative and stable deltas without invention',
    () async {
      final falling = await WaterService(
        repository: _StaticHistoryRepository(
          _history([
            _reading(
              stationId: 'bazias',
              value: 520,
              timestamp: DateTime.utc(2026, 7, 10),
              source: WaterLevelSource.danubeFis,
            ),
            _reading(
              stationId: 'bazias',
              value: 508,
              timestamp: DateTime.utc(2026, 7, 11),
              source: WaterLevelSource.danubeFis,
            ),
          ]),
        ),
      ).getWaterUiResult(_stationWithoutReading());
      final stable = await WaterService(
        repository: _StaticHistoryRepository(
          _history([
            _reading(
              stationId: 'bazias',
              value: 508,
              timestamp: DateTime.utc(2026, 7, 10),
              source: WaterLevelSource.danubeFis,
            ),
            _reading(
              stationId: 'bazias',
              value: 508,
              timestamp: DateTime.utc(2026, 7, 11),
              source: WaterLevelSource.danubeFis,
            ),
          ]),
        ),
      ).getWaterUiResult(_stationWithoutReading());

      expect(falling.deltaCm, -12);
      expect(falling.trend, WaterTrend.falling);
      expect(stable.deltaCm, 0);
      expect(stable.trend, WaterTrend.stable);
    },
  );

  test('one snapshot leaves delta and trend unavailable', () async {
    final result = await WaterService(
      repository: _StaticHistoryRepository(
        _history([
          _reading(
            stationId: 'bazias',
            value: 508,
            timestamp: DateTime.utc(2026, 7, 11),
            source: WaterLevelSource.danubeFis,
          ),
        ]),
      ),
    ).getWaterUiResult(_stationWithoutReading());

    expect(result.deltaCm, isNull);
    expect(result.trend, isNull);
    expect(result.comparisonDuration, isNull);
    expect(result.hasEnoughHistory, isFalse);
  });

  test('a newer live reading is not replaced by an older snapshot', () async {
    final now = _now();
    final live = _reading(
      stationId: 'bazias',
      value: 530,
      timestamp: now.subtract(const Duration(minutes: 5)),
      source: WaterLevelSource.danubeFis,
    );
    final result = await WaterService(
      repository: _StaticHistoryRepository(
        _history([
          _reading(
            stationId: 'bazias',
            value: 500,
            timestamp: now.subtract(const Duration(days: 2)),
            source: WaterLevelSource.danubeFis,
          ),
        ]),
      ),
    ).getWaterUiResult(_stationFrom(live));

    expect(result.latestReading?.value, 530);
    expect(result.latestReading?.timestamp, live.timestamp);
  });

  test(
    'FIS current value is emitted before delayed canonical result',
    () async {
      final repository = _ControlledWaterRepository();
      final station = _stationFrom(
        _reading(
          value: 536,
          timestamp: _now().subtract(const Duration(minutes: 5)),
          source: WaterLevelSource.danubeFis,
        ),
      );
      final iterator = StreamIterator(
        WaterService(
          repository: repository,
        ).getProgressiveWaterUiResults(station),
      );

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.value, 536);
      expect(iterator.current.source, WaterLevelSource.danubeFis);
      expect(repository.historyRequestCount, 1);
      expect(repository.isCanonicalCompleted, isFalse);

      repository.complete(
        const WaterHistoryResult(
          status: WaterHistoryResultStatus.unavailable,
          readings: <WaterLevel>[],
          source: null,
          hadProviderError: false,
        ),
      );
      expect(await iterator.moveNext(), isFalse);
    },
  );

  test('fresh AFDJ reconciles after the FIS fast result', () async {
    final now = _now();
    final repository = _ControlledWaterRepository();
    final iterator = StreamIterator(
      WaterService(repository: repository).getProgressiveWaterUiResults(
        _stationFrom(
          _reading(
            value: 536,
            timestamp: now.subtract(const Duration(minutes: 5)),
            source: WaterLevelSource.danubeFis,
          ),
        ),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    final fastResult = iterator.current;
    expect(fastResult.source, WaterLevelSource.danubeFis);

    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
          trend: WaterTrend.falling,
          hasKnownTrend: true,
        ),
      ]),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.latestReading?.value, 535);
    expect(iterator.current.source, WaterLevelSource.afdj);
    expect(await iterator.moveNext(), isFalse);
  });

  test('AFDJ provider error keeps the real FIS result visible', () async {
    final repository = _ControlledWaterRepository();
    final iterator = StreamIterator(
      WaterService(repository: repository).getProgressiveWaterUiResults(
        _stationFrom(
          _reading(
            value: 536,
            timestamp: _now().subtract(const Duration(minutes: 5)),
            source: WaterLevelSource.danubeFis,
          ),
        ),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    final fastResult = iterator.current;
    expect(fastResult.source, WaterLevelSource.danubeFis);

    repository.complete(
      const WaterHistoryResult(
        status: WaterHistoryResultStatus.providerError,
        readings: <WaterLevel>[],
        source: null,
        hadProviderError: true,
        safeDiagnosticMessage: 'Provider request failed: AFDJ',
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.latestReading?.value, 536);
    expect(iterator.current.source, WaterLevelSource.danubeFis);
    expect(iterator.current.status, WaterUiStatus.insufficientHistory);
    expect(await iterator.moveNext(), isFalse);
  });

  test('slow HIS history does not block the FIS current level', () async {
    final now = _now();
    final repository = _ControlledWaterRepository();
    final iterator = StreamIterator(
      WaterService(repository: repository).getProgressiveWaterUiResults(
        _stationFrom(
          _reading(
            value: 536,
            timestamp: now.subtract(const Duration(minutes: 10)),
            source: WaterLevelSource.danubeFis,
          ),
        ),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.source, WaterLevelSource.danubeFis);
    expect(repository.isCanonicalCompleted, isFalse);

    repository.complete(
      _result([
        _reading(
          value: 540,
          timestamp: now.subtract(const Duration(minutes: 2)),
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.source, WaterLevelSource.danubeHis);
    expect(await iterator.moveNext(), isFalse);
  });

  test('a timestamp over five minutes in the future is rejected', () async {
    final futureReading = _reading(
      value: 999,
      timestamp: _now().add(const Duration(minutes: 6)),
      source: WaterLevelSource.danubeFis,
    );
    final repository = _ControlledWaterRepository()
      ..complete(_result([futureReading]));
    final iterator = StreamIterator(
      WaterService(
        repository: repository,
      ).getProgressiveWaterUiResults(_stationFrom(futureReading)),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.latestReading, isNull);
    expect(iterator.current.status, WaterUiStatus.unavailable);
    expect(await iterator.moveNext(), isFalse);
  });

  test(
    'one historical point keeps trend unknown and history insufficient',
    () async {
      final reading = _reading(
        value: 536,
        timestamp: _now().subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      );
      final repository = _ControlledWaterRepository()
        ..complete(_result([reading]));
      final iterator = StreamIterator(
        WaterService(
          repository: repository,
        ).getProgressiveWaterUiResults(_stationFrom(reading)),
      );

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.hasKnownTrend, isFalse);
      expect(iterator.current.history, isEmpty);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.latestReading?.hasKnownTrend, isFalse);
      expect(iterator.current.history, hasLength(1));
      expect(iterator.current.status, WaterUiStatus.insufficientHistory);
      expect(await iterator.moveNext(), isFalse);
    },
  );

  test(
    'simultaneous progressive requests keep canonical deduplication',
    () async {
      final now = _now();
      final station = _stationFrom(
        _reading(
          value: 536,
          timestamp: now.subtract(const Duration(minutes: 5)),
          source: WaterLevelSource.danubeFis,
        ),
      );
      final repository = _ControlledWaterRepository();
      final service = WaterService(repository: repository);
      final first = StreamIterator(
        service.getProgressiveWaterUiResults(station),
      );
      final second = StreamIterator(
        service.getProgressiveWaterUiResults(station),
      );

      expect(await first.moveNext(), isTrue);
      expect(await second.moveNext(), isTrue);
      expect(repository.historyRequestCount, 1);

      repository.complete(
        _result([
          _reading(
            value: 535,
            timestamp: now.subtract(const Duration(hours: 1)),
            source: WaterLevelSource.afdj,
          ),
        ]),
      );
      expect(await first.moveNext(), isTrue);
      expect(await second.moveNext(), isTrue);
      expect(first.current.source, WaterLevelSource.afdj);
      expect(second.current.source, WaterLevelSource.afdj);
      expect(await first.moveNext(), isFalse);
      expect(await second.moveNext(), isFalse);
    },
  );

  test('simultaneous forced refreshes share one in-flight request', () async {
    final now = _now();
    final station = _stationFrom(
      _reading(
        value: 536,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _ControlledWaterRepository();
    final service = WaterService(repository: repository);
    final first = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );
    final second = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );

    expect(await first.moveNext(), isTrue);
    expect(await second.moveNext(), isTrue);
    expect(repository.historyRequestCount, 1);

    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    expect(await first.moveNext(), isTrue);
    expect(await second.moveNext(), isTrue);
    expect(first.current.source, WaterLevelSource.afdj);
    expect(second.current.source, WaterLevelSource.afdj);
    expect(await first.moveNext(), isFalse);
    expect(await second.moveNext(), isFalse);
  });

  test('forced refresh reuses an active normal request', () async {
    final now = _now();
    final station = _stationFrom(
      _reading(
        value: 536,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _ControlledWaterRepository();
    final service = WaterService(repository: repository);
    final normal = StreamIterator(
      service.getProgressiveWaterUiResults(station),
    );
    final forced = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );

    expect(await normal.moveNext(), isTrue);
    expect(await forced.moveNext(), isTrue);
    expect(repository.historyRequestCount, 1);

    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    expect(await normal.moveNext(), isTrue);
    expect(await forced.moveNext(), isTrue);
    expect(await normal.moveNext(), isFalse);
    expect(await forced.moveNext(), isFalse);
  });

  test('forced refresh after completion bypasses the finished cache', () async {
    final now = _now();
    final station = _stationFrom(
      _reading(
        value: 536,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _ControlledWaterRepository();
    final service = WaterService(repository: repository);
    final first = StreamIterator(service.getProgressiveWaterUiResults(station));

    expect(await first.moveNext(), isTrue);
    repository.complete(
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    expect(await first.moveNext(), isTrue);
    expect(await first.moveNext(), isFalse);
    expect(repository.historyRequestCount, 1);

    final forced = StreamIterator(
      service.getProgressiveWaterUiResults(station, forceRefresh: true),
    );
    expect(await forced.moveNext(), isTrue);
    expect(repository.historyRequestCount, 2);
    expect(await forced.moveNext(), isTrue);
    expect(forced.current.source, WaterLevelSource.afdj);
    expect(await forced.moveNext(), isFalse);
  });

  test('provider error is emitted with the last-known-good reading', () async {
    final now = _now();
    final station = _stationWithoutReading();
    final repository = _SequencedWaterRepository();
    final service = WaterService(repository: repository);
    final initialFuture = service.getWaterUiResult(station, limit: 71);
    repository.complete(
      0,
      _result([
        _reading(
          value: 535,
          timestamp: now.subtract(const Duration(minutes: 5)),
          source: WaterLevelSource.afdj,
        ),
      ]),
    );
    final initial = await initialFuture;
    expect(initial.latestReading?.value, 535);

    final progressive = StreamIterator(
      service.getProgressiveWaterUiResults(station, limit: 72),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.status, isNot(WaterUiStatus.providerError));

    repository.complete(
      1,
      const WaterHistoryResult(
        status: WaterHistoryResultStatus.providerError,
        readings: <WaterLevel>[],
        source: null,
        hadProviderError: true,
        safeDiagnosticMessage: 'Provider request failed: AFDJ',
      ),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.status, WaterUiStatus.providerError);
    expect(progressive.current.latestReading?.value, 535);
    expect(progressive.current.source, WaterLevelSource.afdj);
    expect(await progressive.moveNext(), isFalse);
  });

  test('same measurement emits changed status source and trend', () async {
    final now = _now();
    final station = _stationWithoutReading();
    final repository = _SequencedWaterRepository();
    final service = WaterService(repository: repository);
    final timestamp = now.subtract(const Duration(minutes: 5));
    final initialFuture = service.getWaterUiResult(station, limit: 70);
    repository.complete(
      0,
      _result([
        _reading(
          value: 536,
          timestamp: timestamp,
          source: WaterLevelSource.danubeFis,
        ),
      ]),
    );
    final initial = await initialFuture;
    expect(initial.source, WaterLevelSource.danubeFis);
    expect(initial.latestReading?.hasKnownTrend, isFalse);

    final progressive = StreamIterator(
      service.getProgressiveWaterUiResults(station, limit: 72),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.source, WaterLevelSource.danubeFis);

    repository.complete(
      1,
      _result([
        _reading(
          value: 530,
          timestamp: timestamp.subtract(const Duration(hours: 1)),
          source: WaterLevelSource.danubeHis,
        ),
        _reading(
          value: 536,
          timestamp: timestamp,
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await progressive.moveNext(), isTrue);
    expect(progressive.current.source, WaterLevelSource.danubeHis);
    expect(progressive.current.status, WaterUiStatus.availableHistory);
    expect(progressive.current.latestReading?.trend, WaterTrend.rising);
    expect(progressive.current.latestReading?.hasKnownTrend, isTrue);
    expect(await progressive.moveNext(), isFalse);
  });

  test('delayed station A result remains isolated from station B', () async {
    final now = _now();
    final stationA = _stationFrom(
      _reading(
        stationId: 'station-a',
        value: 100,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final stationB = _stationFrom(
      _reading(
        stationId: 'station-b',
        value: 200,
        timestamp: now.subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
    );
    final repository = _PerStationWaterRepository();
    final service = WaterService(repository: repository);
    final first = StreamIterator(
      service.getProgressiveWaterUiResults(stationA),
    );
    final second = StreamIterator(
      service.getProgressiveWaterUiResults(stationB),
    );

    expect(await first.moveNext(), isTrue);
    expect(await second.moveNext(), isTrue);
    repository.complete(
      'station-b',
      _result([
        _reading(
          stationId: 'station-b',
          value: 201,
          timestamp: now.subtract(const Duration(minutes: 1)),
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await second.moveNext(), isTrue);
    expect(second.current.latestReading?.stationId, 'station-b');

    repository.complete(
      'station-a',
      _result([
        _reading(
          stationId: 'station-a',
          value: 101,
          timestamp: now.subtract(const Duration(minutes: 1)),
          source: WaterLevelSource.danubeHis,
        ),
      ]),
    );
    expect(await first.moveNext(), isTrue);
    expect(first.current.latestReading?.stationId, 'station-a');
    expect(await first.moveNext(), isFalse);
    expect(await second.moveNext(), isFalse);
  });

  test(
    'fresh reading with confirmed online connectivity permits live badge',
    () {
      expect(
        shouldShowWaterLiveBadge(
          hasRealReading: true,
          isStale: false,
          status: WaterUiStatus.insufficientHistory,
          connectivityKnown: true,
          isDefinitelyOffline: false,
        ),
        isTrue,
      );
    },
  );

  test('fresh reading in airplane mode hides live badge', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: true,
      ),
      isFalse,
    );
  });

  test('unknown connectivity hides live badge', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: false,
        isDefinitelyOffline: false,
      ),
      isFalse,
    );
  });

  test('live badge returns when connectivity recovers', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: true,
      ),
      isFalse,
    );
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: false,
      ),
      isTrue,
    );
  });

  test('provider error hides live badge despite confirmed connectivity', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: false,
        status: WaterUiStatus.providerError,
        connectivityKnown: true,
        isDefinitelyOffline: false,
      ),
      isFalse,
    );
  });

  test('stale reading hides live badge despite confirmed connectivity', () {
    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: true,
        isStale: true,
        status: WaterUiStatus.insufficientHistory,
        connectivityKnown: true,
        isDefinitelyOffline: false,
      ),
      isFalse,
    );
  });

  test('offline badge policy preserves the cached water result', () {
    final cachedResult = WaterUiResult(
      latestReading: _reading(
        value: 536,
        timestamp: _now().subtract(const Duration(minutes: 5)),
        source: WaterLevelSource.danubeFis,
      ),
      history: const <WaterLevel>[],
      source: WaterLevelSource.danubeFis,
      sourceName: 'DanubeFIS',
      measurementTimestamp: _now().subtract(const Duration(minutes: 5)),
      dataAge: const Duration(minutes: 5),
      isStale: false,
      status: WaterUiStatus.insufficientHistory,
      safeDiagnosticMessage: null,
    );

    expect(
      shouldShowWaterLiveBadge(
        hasRealReading: cachedResult.latestReading != null,
        isStale: cachedResult.isStale,
        status: cachedResult.status,
        connectivityKnown: true,
        isDefinitelyOffline: true,
      ),
      isFalse,
    );
    expect(cachedResult.latestReading?.value, 536);
  });
}

class _ControlledWaterRepository extends WaterRepository {
  final Completer<WaterHistoryResult> _canonical = Completer();
  int historyRequestCount = 0;

  bool get isCanonicalCompleted => _canonical.isCompleted;

  void complete(WaterHistoryResult result) => _canonical.complete(result);

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) {
    historyRequestCount++;
    return _canonical.future;
  }
}

class _SequencedWaterRepository extends WaterRepository {
  final List<Completer<WaterHistoryResult>> _requests = [];

  void complete(int index, WaterHistoryResult result) {
    _requests[index].complete(result);
  }

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) {
    final request = Completer<WaterHistoryResult>();
    _requests.add(request);
    return request.future;
  }
}

class _PerStationWaterRepository extends WaterRepository {
  final Map<String, Completer<WaterHistoryResult>> _requests = {};

  void complete(String stationId, WaterHistoryResult result) {
    _requests[stationId]!.complete(result);
  }

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) {
    final request = Completer<WaterHistoryResult>();
    _requests[stationId] = request;
    return request.future;
  }
}

class _StaticHistoryRepository extends WaterRepository {
  _StaticHistoryRepository(this.result);

  final WaterHistoryResult result;

  @override
  Future<WaterHistoryResult> getHistoryResult(
    String stationId, {
    String? stationName,
    int limit = 30,
    WaterLevel? prefetchedCurrentReading,
  }) async => result;
}

class _FakeSnapshotReader implements DailyWaterSnapshotReader {
  _FakeSnapshotReader(this.rows);

  final List<Map<String, Object?>> rows;
  final List<String> stationIds = <String>[];
  final List<int> limits = <int>[];

  @override
  Future<List<Map<String, Object?>>> readStationHistory(
    String stationId, {
    required int limit,
  }) async {
    stationIds.add(stationId);
    limits.add(limit);
    return rows;
  }
}

WaterHistoryResult _history(List<WaterLevel> readings) => WaterHistoryResult(
  status: readings.length >= 2
      ? WaterHistoryResultStatus.success
      : WaterHistoryResultStatus.insufficientHistory,
  readings: readings,
  source: readings.isEmpty ? null : readings.last.source,
  hadProviderError: false,
);

Map<String, Object?> _snapshotRow({
  required String stationId,
  required String observationDate,
  required Object? level,
  required DateTime measuredAt,
  String source = 'DanubeFIS',
  String quality = 'valid',
}) => {
  'station_id': stationId,
  'observation_date': observationDate,
  'level_cm': level,
  'level_source': source,
  'level_measured_at': measuredAt.toIso8601String(),
  'quality': quality,
};

WaterHistoryResult _result(List<WaterLevel> readings) => WaterHistoryResult(
  status: readings.length >= 2
      ? WaterHistoryResultStatus.success
      : readings.isEmpty
      ? WaterHistoryResultStatus.unavailable
      : WaterHistoryResultStatus.insufficientHistory,
  readings: readings,
  source: readings.isEmpty ? null : readings.last.source,
  hadProviderError: false,
);

DateTime _now() => DateTime.now().toUtc();

WaterLevel _reading({
  String stationId = 'bazias',
  required double value,
  required DateTime timestamp,
  required WaterLevelSource source,
  WaterTrend trend = WaterTrend.stable,
  bool hasKnownTrend = false,
}) => WaterLevel(
  stationId: stationId,
  value: value,
  timestamp: timestamp,
  trend: trend,
  source: source,
  sourceName: source.name,
  hasKnownTrend: hasKnownTrend,
);

Station _stationFrom(WaterLevel reading) => Station(
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

Station _stationWithoutReading() => Station(
  id: 'bazias',
  name: 'Bazias',
  river: 'Dunarea',
  level: 0,
  trend: WaterTrend.stable,
  latitude: 44.8167,
  longitude: 21.3833,
  lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  hasWaterLevel: false,
);

Station _homeStation(
  String id,
  String name,
  double latitude,
  double longitude, {
  bool hasReading = true,
}) => Station(
  id: id,
  name: name,
  river: 'Dunarea',
  level: hasReading ? 300 : 0,
  trend: WaterTrend.stable,
  latitude: latitude,
  longitude: longitude,
  lastUpdate: DateTime.utc(2026, 7, 16),
  hasWaterLevel: hasReading,
  waterLevelSource: 'DanubeFIS',
);
