import 'dart:async';

import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/widgets/home_premium/water_level_card.dart'
    show shouldShowWaterLiveBadge;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(WaterService.clearCache);

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
