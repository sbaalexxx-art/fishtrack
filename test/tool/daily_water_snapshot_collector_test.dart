import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart';

import '../../tool/src/daily_water_snapshot_collector.dart';

void main() {
  setUpAll(initializeTimeZones);
  const builder = DailyWaterSnapshotBuilder();
  final now = DateTime.utc(2026, 1, 15, 12);

  ProviderReading reading(SnapshotSource source, int value, DateTime time) =>
      ProviderReading(source: source, levelCm: value, measuredAt: time);

  test('provider-reported delta is preserved', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [reading(SnapshotSource.danubeHis, 500, now)],
      reportedDeltas: [
        ProviderReportedDelta(
          deltaCm: 4,
          source: SnapshotSource.afdj,
          measuredAt: now,
        ),
      ],
    );
    expect(payload.dailyDeltaCm, 4);
    expect(payload.deltaMethod, 'provider_reported');
    expect(payload.deltaBaseMeasuredAt, isNull);
  });

  test('provider-reported wins over computed delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.danubeHis,
          500,
          now.subtract(const Duration(days: 1)),
        ),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
      reportedDeltas: [
        ProviderReportedDelta(
          deltaCm: 2,
          source: SnapshotSource.afdj,
          measuredAt: now,
        ),
      ],
    );
    expect(payload.dailyDeltaCm, 2);
    expect(payload.deltaMethod, 'provider_reported');
  });

  test('same-source history computes a delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.danubeHis,
          500,
          now.subtract(const Duration(days: 1)),
        ),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
    );
    expect(payload.dailyDeltaCm, 10);
    expect(payload.deltaMethod, 'computed_same_source');
    expect(payload.deltaBaseMeasuredAt, now.subtract(const Duration(days: 1)));
  });

  test('different sources do not compute a delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.afdj,
          500,
          now.subtract(const Duration(days: 1)),
        ),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
    );
    expect(payload.deltaMethod, 'unavailable');
    expect(payload.dailyDeltaCm, isNull);
  });

  test('newer or equal base cannot produce delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(SnapshotSource.danubeHis, 500, now),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
    );
    expect(payload.deltaMethod, 'unavailable');
  });

  test('unavailable delta has null pairing fields', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [reading(SnapshotSource.danubeFis, 500, now)],
    );
    expect(payload.toJson()['daily_delta_cm'], isNull);
    expect(payload.toJson()['delta_source'], isNull);
    expect(payload.toJson()['delta_measured_at'], isNull);
    expect(payload.toJson()['delta_base_measured_at'], isNull);
  });

  test('level and delta preserve separate timestamps', () {
    final base = now.subtract(const Duration(hours: 24));
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(SnapshotSource.danubeHis, 490, base),
        reading(SnapshotSource.danubeHis, 500, now),
      ],
    );
    expect(payload.levelMeasuredAt, now);
    expect(payload.deltaMeasuredAt, now);
    expect(payload.deltaBaseMeasuredAt, base);
  });

  test('valid level is not replaced by failure', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [reading(SnapshotSource.danubeFis, 500, now)],
      failures: const [ProviderFailure(SnapshotSource.afdj, 'offline')],
    );
    expect(payload.levelCm, 500);
    expect(payload.quality, 'partial');
  });

  test('provider failures without data produce provider_error', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      failures: const [ProviderFailure(SnapshotSource.afdj, 'offline')],
      readings: const [],
    );
    expect(payload.quality, 'provider_error');
  });

  test('quality values are limited to SQL contract', () {
    expect(
      SnapshotQuality.values.map((value) => value.databaseValue),
      containsAll(<String>[
        'valid',
        'partial',
        'stale',
        'provider_error',
        'unknown',
      ]),
    );
  });

  test('payload uses quality and never quality_status', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: const [],
    );
    expect(payload.toJson().containsKey('quality'), isTrue);
    expect(payload.toJson().containsKey('quality_status'), isFalse);
  });

  test('winter Bucharest date differs at UTC midnight boundary', () {
    expect(
      DailyWaterSnapshotBuilder.observationDateFor(
        DateTime.utc(2026, 1, 1, 22, 30),
      ),
      '2026-01-02',
    );
  });

  test('summer Bucharest date uses DST', () {
    expect(
      DailyWaterSnapshotBuilder.observationDateFor(
        DateTime.utc(2026, 7, 1, 21, 30),
      ),
      '2026-07-02',
    );
  });

  test('UTC midnight proximity keeps Bucharest calendar day', () {
    expect(
      DailyWaterSnapshotBuilder.observationDateFor(
        DateTime.utc(2026, 1, 1, 21, 30),
      ),
      '2026-01-01',
    );
  });

  test('same input is deterministic', () {
    final readings = [
      reading(
        SnapshotSource.danubeHis,
        500,
        now.subtract(const Duration(hours: 2)),
      ),
      reading(SnapshotSource.danubeHis, 505, now),
    ];
    expect(
      builder
          .build(stationId: 'bazias', nowUtc: now, readings: readings)
          .toJson(),
      builder
          .build(stationId: 'bazias', nowUtc: now, readings: readings)
          .toJson(),
    );
  });

  test('provider order does not change payload', () {
    final first = [
      reading(SnapshotSource.danubeFis, 500, now),
      reading(
        SnapshotSource.danubeHis,
        490,
        now.subtract(const Duration(hours: 2)),
      ),
      reading(SnapshotSource.danubeHis, 495, now),
    ];
    expect(
      builder.build(stationId: 'bazias', nowUtc: now, readings: first).toJson(),
      builder
          .build(stationId: 'bazias', nowUtc: now, readings: first.reversed)
          .toJson(),
    );
  });

  test('level pairing is all-null without readings', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: const [],
    );
    expect([
      payload.levelCm,
      payload.levelSource,
      payload.levelMeasuredAt,
    ], everyElement(isNull));
  });

  test('empty successful collection is classified unknown', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: const [],
    );
    expect(payload.quality, 'unknown');
  });

  test('stale data is classified stale', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.danubeFis,
          500,
          now.subtract(const Duration(hours: 37)),
        ),
      ],
    );
    expect(payload.quality, 'stale');
  });

  test('summary classifies results and missing deltas', () {
    final valid = StationSnapshotResult(
      stationId: 'a',
      stationName: 'A',
      failures: const [],
      payload: builder.build(
        stationId: 'a',
        nowUtc: now,
        readings: [
          reading(
            SnapshotSource.danubeHis,
            1,
            now.subtract(const Duration(hours: 1)),
          ),
          reading(SnapshotSource.danubeHis, 2, now),
        ],
      ),
    );
    final partial = StationSnapshotResult(
      stationId: 'b',
      stationName: 'B',
      failures: const [],
      payload: builder.build(
        stationId: 'b',
        nowUtc: now,
        readings: [reading(SnapshotSource.danubeFis, 1, now)],
      ),
    );
    final summary = SnapshotRunSummary([valid, partial]);
    expect(summary.valid, 1);
    expect(summary.partial, 1);
    expect(summary.withoutDelta, 1);
  });
}
