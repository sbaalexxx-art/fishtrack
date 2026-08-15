import 'package:fishtrack/core/water/water_history_analysis.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/screens/water_level_page.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/widgets/home_premium/water_level_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final epoch = DateTime.utc(2026, 8, 1);

  test('rising real sequence uses latest value and robust rising trend', () {
    final result = canonicalWaterTrendResult([
      _reading(100, epoch),
      _reading(102, epoch.add(const Duration(hours: 12))),
      _reading(105, epoch.add(const Duration(hours: 24))),
    ])!;

    expect(result.currentValue, 105);
    expect(result.delta?.value, 5);
    expect(result.delta?.referenceValue, 100);
    expect(result.trend.direction, WaterDirection.rising);
    expect(result.trend.observationsUsed, 3);
  });

  test('falling real sequence produces falling direction', () {
    final result = canonicalWaterTrendResult([
      _reading(110, epoch),
      _reading(106, epoch.add(const Duration(hours: 8))),
      _reading(101, epoch.add(const Duration(hours: 16))),
    ])!;

    expect(result.delta?.value, -5);
    expect(result.trend.direction, WaterDirection.falling);
  });

  test('stable classification respects supplied measurement resolution', () {
    final result = canonicalWaterTrendResult([
      _reading(100, epoch, resolution: 1),
      _reading(100.4, epoch.add(const Duration(hours: 6)), resolution: 1),
      _reading(100.2, epoch.add(const Duration(hours: 12)), resolution: 1),
    ])!;

    expect(result.trend.direction, WaterDirection.stable);
    expect(result.trend.robustRate, isNotNull);
  });

  test(
    'oscillating multi-point sequence is not reduced to latest delta sign',
    () {
      final result = canonicalWaterTrendResult([
        _reading(100, epoch),
        _reading(110, epoch.add(const Duration(hours: 1))),
        _reading(90, epoch.add(const Duration(hours: 2))),
        _reading(105, epoch.add(const Duration(hours: 3))),
      ])!;

      expect(result.delta?.value, 15);
      expect(result.trend.direction, WaterDirection.oscillating);
    },
  );

  test('exact compatible 24 hour observation gets exact24Hours semantics', () {
    final result = canonicalWaterTrendResult([
      _reading(80, epoch),
      _reading(84, epoch.add(const Duration(hours: 20))),
      _reading(90, epoch.add(const Duration(hours: 24))),
    ])!;

    expect(result.delta?.referenceValue, 80);
    expect(result.delta?.actualInterval, const Duration(hours: 24));
    expect(result.delta?.comparisonType, WaterComparisonType.exact24Hours);
  });

  test('Station panel 24h delta uses only a valid real observation pair', () {
    final valid = realWaterIntervalDelta(
      [
        _reading(694, epoch),
        _reading(692, epoch.add(const Duration(hours: 24))),
      ],
      const Duration(hours: 24),
      stationId: 'station-1',
    );
    final unavailable = realWaterIntervalDelta(
      [
        _reading(694, epoch),
        _reading(692, epoch.add(const Duration(hours: 12))),
      ],
      const Duration(hours: 24),
      stationId: 'station-1',
    );

    expect(valid?.to.value, 692);
    expect(valid?.deltaCm, -2);
    expect(valid?.actualInterval, const Duration(hours: 24));
    expect(valid?.trend, WaterTrend.falling);
    expect(unavailable, isNull);
  });

  test('exact non-24h comparison exposes its actual interval', () {
    final result = canonicalWaterTrendResult([
      _reading(80, epoch),
      _reading(86, epoch.add(const Duration(hours: 7))),
    ])!;

    expect(result.delta?.value, 6);
    expect(result.delta?.actualInterval, const Duration(hours: 7));
    expect(result.delta?.comparisonType, WaterComparisonType.actualInterval);
  });

  test('consecutive AFDJ date-only observations produce daily semantics', () {
    final result = canonicalWaterTrendResult([
      _reading(95, epoch, precision: WaterMeasurementPrecision.date),
      _reading(
        98,
        epoch.add(const Duration(days: 1)),
        precision: WaterMeasurementPrecision.date,
      ),
    ])!;

    expect(result.delta?.value, 3);
    expect(result.delta?.comparisonType, WaterComparisonType.daily);
    expect(result.trend.rateUnit, WaterRateUnit.valuePerDay);
  });

  test('missing observations return no canonical current result', () {
    expect(canonicalWaterTrendResult(const <WaterLevel>[]), isNull);
  });

  test('one real observation exposes current value without delta or line', () {
    final observation = _reading(42, epoch);
    final result = canonicalWaterTrendResult([observation])!;

    expect(result.currentValue, 42);
    expect(result.delta, isNull);
    expect(result.trend.direction, WaterDirection.unknown);
    expect(result.history.realSegments.single.hasVisualLine, isFalse);
  });

  test('unknown never falls back to stable in Home presentation', () {
    final observation = _reading(42, epoch);
    final canonical = canonicalWaterTrendResult([observation])!;
    final result = WaterUiResult(
      latestReading: observation,
      history: [observation],
      source: observation.source,
      sourceName: observation.sourceName,
      measurementTimestamp: observation.timestamp,
      dataAge: Duration.zero,
      isStale: false,
      status: WaterUiStatus.insufficientHistory,
      safeDiagnosticMessage: null,
      trend: null,
      canonicalTrend: canonical,
    );

    expect(observation.trend, WaterTrend.stable);
    expect(observation.knownTrend, isNull);
    expect(resolvedHomeWaterTrend(result), isNull);
    final copy = resolveHomeWaterSemanticPresentation(
      dailyDelta: result.deltaCm,
      trend: resolvedHomeWaterTrend(result),
      isRomanian: true,
    );
    expect(copy.primary, 'Trend indisponibil');
    expect(copy.primary, isNot(contains('Stabil')));
    expect(copy.primary, isNot(contains('0 cm')));
    expect(copy.primary, isNot(contains('cm / 24h')));
  });

  test('two observations are one straight-eligible non-spline segment', () {
    final result = canonicalWaterTrendResult([
      _reading(10, epoch),
      _reading(12, epoch.add(const Duration(hours: 2))),
    ])!;
    final segment = result.history.realSegments.single;

    expect(segment.realObservations, hasLength(2));
    expect(segment.hasVisualLine, isTrue);
    expect(segment.isSplineEligible, isFalse);
  });

  test('irregular timestamps use median pairwise Theil-Sen style rate', () {
    final result = canonicalWaterTrendResult([
      _reading(10, epoch),
      _reading(16, epoch.add(const Duration(hours: 3))),
      _reading(30, epoch.add(const Duration(hours: 10))),
    ])!;

    expect(result.trend.robustRate, closeTo(2, 0.000001));
    expect(result.trend.rateUnit, WaterRateUnit.valuePerHour);
    expect(result.trend.analysisSpan, const Duration(hours: 10));
  });

  test('significant temporal gap creates separate real chart segments', () {
    final readings = [
      _reading(10, epoch, precision: WaterMeasurementPrecision.date),
      _reading(
        11,
        epoch.add(const Duration(days: 1)),
        precision: WaterMeasurementPrecision.date,
      ),
      _reading(
        12,
        epoch.add(const Duration(days: 2)),
        precision: WaterMeasurementPrecision.date,
      ),
      _reading(
        15,
        epoch.add(const Duration(days: 10)),
        precision: WaterMeasurementPrecision.date,
      ),
    ];
    final result = canonicalWaterTrendResult(readings)!;

    expect(result.history.gapThreshold, const Duration(hours: 36));
    expect(
      result.history.realSegments.map(
        (segment) => segment.realObservations.length,
      ),
      [3, 1],
    );
  });

  test('incompatible source metric unit datum and quality are excluded', () {
    final current = _reading(20, epoch.add(const Duration(hours: 24)));
    final result = canonicalWaterTrendResult([
      _reading(1, epoch, source: WaterLevelSource.manualFallback),
      _reading(2, epoch.add(const Duration(hours: 1)), metric: 'flow'),
      _reading(3, epoch.add(const Duration(hours: 2)), unit: 'm'),
      _reading(4, epoch.add(const Duration(hours: 3)), datum: 'other'),
      _reading(
        5,
        epoch.add(const Duration(hours: 4)),
        historyContract: 'other',
      ),
      _reading(6, epoch.add(const Duration(hours: 5)), qualityValid: false),
    ], currentObservation: current)!;

    expect(result.history.realObservations, [current]);
    expect(result.delta, isNull);
  });

  test('negative valid latest water level is preserved without clamping', () {
    final result = canonicalWaterTrendResult([
      _reading(-12, epoch),
      _reading(-18, epoch.add(const Duration(hours: 6))),
    ])!;

    expect(result.currentValue, -18);
    expect(result.delta?.value, -6);
    expect(result.trend.direction, WaterDirection.falling);
  });

  test('Home and Water Hub consume the identical canonical result', () {
    final history = [_reading(10, epoch)];
    final canonical = canonicalWaterTrendResult(history)!;
    final result = WaterUiResult(
      latestReading: history.last,
      history: history,
      source: WaterLevelSource.afdj,
      sourceName: 'AFDJ',
      measurementTimestamp: history.last.timestamp,
      dataAge: Duration.zero,
      isStale: false,
      status: WaterUiStatus.insufficientHistory,
      safeDiagnosticMessage: null,
      canonicalTrend: canonical,
    );

    final home = homeWaterCanonicalTrend(result);
    final hub = waterHubCanonicalTrend(result);
    expect(identical(home, hub), isTrue);
    expect(home?.delta?.value, hub?.delta?.value);
    expect(home?.trend.direction, hub?.trend.direction);
    expect(home?.currentValue, hub?.currentValue);
    expect(home?.currentMeasurementAt, hub?.currentMeasurementAt);
    expect(home?.freshnessAt, hub?.freshnessAt);
    expect(home?.trend.direction, WaterDirection.unknown);
    expect(home?.delta, isNull);
  });

  test('freshness changes do not alter measurement delta or trend', () {
    final first = [
      _reading(30, epoch, freshness: epoch.add(const Duration(hours: 1))),
      _reading(
        36,
        epoch.add(const Duration(hours: 6)),
        freshness: epoch.add(const Duration(hours: 7)),
      ),
    ];
    final second = [
      _reading(30, epoch, freshness: epoch.add(const Duration(days: 3))),
      _reading(
        36,
        epoch.add(const Duration(hours: 6)),
        freshness: epoch.add(const Duration(days: 4)),
      ),
    ];

    final firstResult = canonicalWaterTrendResult(first)!;
    final secondResult = canonicalWaterTrendResult(second)!;
    expect(firstResult.delta?.value, secondResult.delta?.value);
    expect(firstResult.trend.direction, secondResult.trend.direction);
    expect(firstResult.freshnessAt, isNot(secondResult.freshnessAt));
  });

  test(
    'chart history contains every source observation once and no fabrication',
    () {
      final readings = [
        _reading(1, epoch),
        _reading(2, epoch.add(const Duration(hours: 1))),
        _reading(3, epoch.add(const Duration(hours: 2))),
        _reading(4, epoch.add(const Duration(hours: 12))),
      ];
      final result = canonicalWaterTrendResult(readings)!;
      final flattened = result.history.realSegments
          .expand((segment) => segment.realObservations)
          .toList(growable: false);

      expect(flattened, hasLength(readings.length));
      for (var index = 0; index < readings.length; index++) {
        expect(identical(flattened[index], readings[index]), isTrue);
      }
    },
  );
}

WaterLevel _reading(
  double value,
  DateTime timestamp, {
  DateTime? freshness,
  WaterMeasurementPrecision precision = WaterMeasurementPrecision.exact,
  WaterLevelSource source = WaterLevelSource.afdj,
  String metric = 'water_level',
  String unit = 'cm',
  String datum = 'source_native',
  String historyContract = 'canonical_water_level',
  bool qualityValid = true,
  double? resolution,
}) {
  return WaterLevel(
    stationId: 'station-1',
    value: value,
    timestamp: timestamp,
    freshnessTimestamp: freshness,
    measurementPrecision: precision,
    trend: WaterTrend.stable,
    source: source,
    unit: unit,
    sourceName: source.name,
    metricCode: metric,
    measurementDatum: datum,
    historyContract: historyContract,
    isQualityValid: qualityValid,
    measurementResolution: resolution,
  );
}
