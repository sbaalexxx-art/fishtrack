import 'dart:math' as math;

import '../../models/station.dart';
import '../../models/water_level.dart';

const Duration canonicalWater24HourTolerance = Duration(hours: 4);

enum WaterHistoryRange {
  sevenDays(Duration(days: 7)),
  thirtyDays(Duration(days: 30));

  const WaterHistoryRange(this.duration);

  final Duration duration;
}

enum WaterDirection { rising, stable, falling, oscillating, unknown }

enum WaterComparisonType { exact24Hours, actualInterval, daily }

enum WaterRateUnit { valuePerHour, valuePerDay }

enum WaterTrendConfidence { insufficient, low, medium, high }

class WaterDeltaResult {
  const WaterDeltaResult({
    required this.value,
    required this.referenceValue,
    required this.referenceMeasurementAt,
    required this.actualInterval,
    required this.comparisonType,
    required this.referenceObservation,
  });

  final double value;
  final double referenceValue;
  final DateTime referenceMeasurementAt;
  final Duration actualInterval;
  final WaterComparisonType comparisonType;
  final WaterLevel referenceObservation;
}

class WaterTrendAnalysis {
  const WaterTrendAnalysis({
    required this.direction,
    required this.robustRate,
    required this.rateUnit,
    required this.observationsUsed,
    required this.analysisSpan,
    required this.consistency,
    required this.confidence,
  });

  final WaterDirection direction;
  final double? robustRate;
  final WaterRateUnit? rateUnit;
  final int observationsUsed;
  final Duration? analysisSpan;
  final double consistency;
  final WaterTrendConfidence confidence;

  WaterTrend? get displayTrend => switch (direction) {
    WaterDirection.rising => WaterTrend.rising,
    WaterDirection.stable => WaterTrend.stable,
    WaterDirection.falling => WaterTrend.falling,
    WaterDirection.oscillating || WaterDirection.unknown => null,
  };
}

class WaterHistorySegment {
  const WaterHistorySegment(this.realObservations);

  final List<WaterLevel> realObservations;

  bool get hasVisualLine => realObservations.length >= 2;
  bool get isSplineEligible => realObservations.length >= 3;
}

class WaterTrendHistory {
  const WaterTrendHistory({
    required this.realObservations,
    required this.realSegments,
    required this.gapThreshold,
  });

  final List<WaterLevel> realObservations;
  final List<WaterHistorySegment> realSegments;
  final Duration? gapThreshold;
}

class WaterTrendResult {
  const WaterTrendResult({
    required this.currentValue,
    required this.currentMeasurementAt,
    required this.measurementPrecision,
    required this.freshnessAt,
    required this.delta,
    required this.trend,
    required this.history,
  });

  final double currentValue;
  final DateTime currentMeasurementAt;
  final WaterMeasurementPrecision measurementPrecision;
  final DateTime freshnessAt;
  final WaterDeltaResult? delta;
  final WaterTrendAnalysis trend;
  final WaterTrendHistory history;
}

WaterTrendResult? canonicalWaterTrendResult(
  List<WaterLevel> observations, {
  WaterLevel? currentObservation,
  String? stationId,
}) {
  final valid = observations.where(_isValidObservation).toList(growable: true);
  if (currentObservation != null && _isValidObservation(currentObservation)) {
    valid.add(currentObservation);
  }
  if (valid.isEmpty) return null;

  final requestedStation = stationId == null
      ? null
      : _normalizedStationKey(stationId);
  if (requestedStation != null) {
    valid.removeWhere(
      (reading) => _normalizedStationKey(reading.stationId) != requestedStation,
    );
  }
  if (valid.isEmpty) return null;

  valid.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final current =
      currentObservation != null &&
          _isValidObservation(currentObservation) &&
          (requestedStation == null ||
              _normalizedStationKey(currentObservation.stationId) ==
                  requestedStation)
      ? currentObservation
      : valid.last;

  final byMeasurementTime = <int, WaterLevel>{};
  for (final reading in valid) {
    if (reading.timestamp.isAfter(current.timestamp) ||
        !_observationsAreCompatible(reading, current)) {
      continue;
    }
    byMeasurementTime[reading.timestamp.toUtc().microsecondsSinceEpoch] =
        reading;
  }
  byMeasurementTime[current.timestamp.toUtc().microsecondsSinceEpoch] = current;
  final series = byMeasurementTime.values.toList(growable: false)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final history = _buildTrendHistory(series);
  final delta = _buildCanonicalDelta(series);
  final trend = _buildRobustTrend(series);
  return WaterTrendResult(
    currentValue: current.value,
    currentMeasurementAt: current.timestamp,
    measurementPrecision: current.measurementPrecision,
    freshnessAt: current.effectiveFreshnessTimestamp,
    delta: delta,
    trend: trend,
    history: history,
  );
}

List<WaterLevel> realWaterHistoryForRange(
  List<WaterLevel> history,
  WaterHistoryRange range, {
  String? stationId,
}) => realWaterHistorySeries(
  history,
  period: range.duration,
  stationId: stationId,
);

List<WaterLevel> realWaterHistorySeries(
  List<WaterLevel> history, {
  required Duration period,
  String? stationId,
}) {
  final analysis = canonicalWaterTrendResult(history, stationId: stationId);
  final valid = analysis?.history.realObservations ?? const <WaterLevel>[];
  if (valid.isEmpty) return const <WaterLevel>[];

  final cutoff = valid.last.timestamp.subtract(period);
  return List<WaterLevel>.unmodifiable(
    valid.where((reading) => !reading.timestamp.isBefore(cutoff)),
  );
}

List<List<WaterLevel>> realWaterHistorySegments(
  List<WaterLevel> history, {
  String? stationId,
}) {
  final analysis = canonicalWaterTrendResult(history, stationId: stationId);
  if (analysis == null) return const <List<WaterLevel>>[];
  return List<List<WaterLevel>>.unmodifiable(
    analysis.history.realSegments
        .map((segment) => segment.realObservations)
        .toList(growable: false),
  );
}

WaterTrend? waterTrendFromRealDelta(
  double? delta, {
  double? measurementResolution,
}) {
  if (delta == null || !delta.isFinite) return null;
  if (_isEffectivelyStable(delta, measurementResolution)) {
    return WaterTrend.stable;
  }
  return delta > 0 ? WaterTrend.rising : WaterTrend.falling;
}

double? realWaterSeriesDelta(List<WaterLevel> history) =>
    history.length < 2 ? null : history.last.value - history.first.value;

class WaterIntervalDelta {
  const WaterIntervalDelta({
    required this.targetInterval,
    required this.actualInterval,
    required this.deltaCm,
    required this.from,
    required this.to,
  });

  final Duration targetInterval;
  final Duration actualInterval;
  final double deltaCm;
  final WaterLevel from;
  final WaterLevel to;

  WaterTrend get trend => waterTrendFromRealDelta(
    deltaCm,
    measurementResolution: _combinedResolution(from, to),
  )!;
}

WaterIntervalDelta? realWaterIntervalDelta(
  List<WaterLevel> history,
  Duration targetInterval, {
  String? stationId,
  Duration? tolerance,
}) {
  final analysis = canonicalWaterTrendResult(history, stationId: stationId);
  final series = analysis?.history.realObservations ?? const <WaterLevel>[];
  if (series.length < 2) return null;

  final latest = series.last;
  final targetTimestamp = latest.timestamp.subtract(targetInterval);
  WaterLevel? nearest;
  Duration? nearestDistance;
  for (final candidate in series.take(series.length - 1)) {
    final distance = candidate.timestamp.difference(targetTimestamp).abs();
    if (nearestDistance == null || distance < nearestDistance) {
      nearest = candidate;
      nearestDistance = distance;
    }
  }
  final allowed = tolerance ?? _defaultIntervalTolerance(targetInterval);
  if (nearest == null || nearestDistance == null || nearestDistance > allowed) {
    return null;
  }
  return WaterIntervalDelta(
    targetInterval: targetInterval,
    actualInterval: latest.timestamp.difference(nearest.timestamp),
    deltaCm: latest.value - nearest.value,
    from: nearest,
    to: latest,
  );
}

WaterDeltaResult? _buildCanonicalDelta(List<WaterLevel> series) {
  if (series.length < 2) return null;
  final current = series.last;
  final candidates = series.take(series.length - 1).toList(growable: false);
  WaterLevel? reference;
  var comparisonType = WaterComparisonType.actualInterval;

  if (current.measurementPrecision == WaterMeasurementPrecision.exact) {
    final target = current.timestamp.subtract(const Duration(hours: 24));
    Duration? nearestDistance;
    for (final candidate in candidates) {
      if (candidate.measurementPrecision != WaterMeasurementPrecision.exact) {
        continue;
      }
      final distance = candidate.timestamp.difference(target).abs();
      if (nearestDistance == null || distance < nearestDistance) {
        reference = candidate;
        nearestDistance = distance;
      }
    }
    if (reference != null &&
        nearestDistance != null &&
        nearestDistance <= canonicalWater24HourTolerance) {
      comparisonType = WaterComparisonType.exact24Hours;
    } else {
      reference = candidates.last;
    }
  } else if (current.measurementPrecision == WaterMeasurementPrecision.date) {
    for (final candidate in candidates.reversed) {
      if (candidate.measurementPrecision != WaterMeasurementPrecision.date) {
        continue;
      }
      reference = candidate;
      break;
    }
    if (reference != null &&
        _utcCalendarDayDistance(reference.timestamp, current.timestamp) == 1) {
      comparisonType = WaterComparisonType.daily;
    }
  } else {
    reference = candidates.last;
  }

  if (reference == null) return null;
  return WaterDeltaResult(
    value: current.value - reference.value,
    referenceValue: reference.value,
    referenceMeasurementAt: reference.timestamp,
    actualInterval: current.timestamp.difference(reference.timestamp),
    comparisonType: comparisonType,
    referenceObservation: reference,
  );
}

WaterTrendAnalysis _buildRobustTrend(List<WaterLevel> series) {
  if (series.length < 2) {
    return WaterTrendAnalysis(
      direction: WaterDirection.unknown,
      robustRate: null,
      rateUnit: null,
      observationsUsed: series.length,
      analysisSpan: null,
      consistency: 0,
      confidence: WaterTrendConfidence.insufficient,
    );
  }

  final useDays = series.every(
    (reading) => reading.measurementPrecision == WaterMeasurementPrecision.date,
  );
  final slopes = <double>[];
  for (var first = 0; first < series.length - 1; first++) {
    for (var second = first + 1; second < series.length; second++) {
      final interval = series[second].timestamp.difference(
        series[first].timestamp,
      );
      final units = useDays
          ? interval.inMicroseconds / Duration.microsecondsPerDay
          : interval.inMicroseconds / Duration.microsecondsPerHour;
      if (units <= 0) continue;
      slopes.add((series[second].value - series[first].value) / units);
    }
  }
  if (slopes.isEmpty) {
    return WaterTrendAnalysis(
      direction: WaterDirection.unknown,
      robustRate: null,
      rateUnit: null,
      observationsUsed: series.length,
      analysisSpan: null,
      consistency: 0,
      confidence: WaterTrendConfidence.insufficient,
    );
  }

  slopes.sort();
  final robustRate = _median(slopes);
  final span = series.last.timestamp.difference(series.first.timestamp);
  final spanUnits = useDays
      ? span.inMicroseconds / Duration.microsecondsPerDay
      : span.inMicroseconds / Duration.microsecondsPerHour;
  final resolution = series
      .map((reading) => _validResolution(reading.measurementResolution))
      .whereType<double>()
      .fold<double?>(
        null,
        (current, value) => math.max(current ?? value, value),
      );
  final robustChange = robustRate * spanUnits;
  var robustDirection = _directionForChange(robustChange, resolution);

  var risingSteps = 0;
  var fallingSteps = 0;
  var stableSteps = 0;
  for (var index = 1; index < series.length; index++) {
    final change = series[index].value - series[index - 1].value;
    final direction = _directionForChange(
      change,
      _combinedResolution(series[index - 1], series[index]),
    );
    switch (direction) {
      case WaterDirection.rising:
        risingSteps++;
      case WaterDirection.falling:
        fallingSteps++;
      case WaterDirection.stable:
        stableSteps++;
      case WaterDirection.oscillating:
      case WaterDirection.unknown:
        break;
    }
  }

  final stepCount = risingSteps + fallingSteps + stableSteps;
  final agreeingSteps = switch (robustDirection) {
    WaterDirection.rising => risingSteps,
    WaterDirection.falling => fallingSteps,
    WaterDirection.stable => stableSteps,
    WaterDirection.oscillating || WaterDirection.unknown => 0,
  };
  final consistency = stepCount == 0 ? 0.0 : agreeingSteps / stepCount;
  if (risingSteps > 0 && fallingSteps > 0 && consistency < (2 / 3)) {
    robustDirection = WaterDirection.oscillating;
  }

  final confidence = switch (series.length) {
    < 2 => WaterTrendConfidence.insufficient,
    2 => WaterTrendConfidence.low,
    >= 5 when consistency >= .8 => WaterTrendConfidence.high,
    >= 3 when consistency >= (2 / 3) => WaterTrendConfidence.medium,
    _ => WaterTrendConfidence.low,
  };
  return WaterTrendAnalysis(
    direction: robustDirection,
    robustRate: robustRate,
    rateUnit: useDays ? WaterRateUnit.valuePerDay : WaterRateUnit.valuePerHour,
    observationsUsed: series.length,
    analysisSpan: span,
    consistency: consistency,
    confidence: confidence,
  );
}

WaterTrendHistory _buildTrendHistory(List<WaterLevel> series) {
  if (series.isEmpty) {
    return const WaterTrendHistory(
      realObservations: <WaterLevel>[],
      realSegments: <WaterHistorySegment>[],
      gapThreshold: null,
    );
  }
  if (series.length == 1) {
    final observations = List<WaterLevel>.unmodifiable(series);
    return WaterTrendHistory(
      realObservations: observations,
      realSegments: <WaterHistorySegment>[WaterHistorySegment(observations)],
      gapThreshold: null,
    );
  }

  final gaps = <Duration>[];
  for (var index = 1; index < series.length; index++) {
    final gap = series[index].timestamp.difference(series[index - 1].timestamp);
    if (gap > Duration.zero) gaps.add(gap);
  }
  final sortedGapMicros =
      gaps.map((gap) => gap.inMicroseconds).toList(growable: false)..sort();
  final lowerMedianGap = sortedGapMicros[(sortedGapMicros.length - 1) ~/ 2];
  final dynamicGapThreshold = Duration(microseconds: lowerMedianGap * 3);
  final allDateOnly = series.every(
    (reading) => reading.measurementPrecision == WaterMeasurementPrecision.date,
  );
  final gapThreshold =
      allDateOnly && dynamicGapThreshold > const Duration(hours: 36)
      ? const Duration(hours: 36)
      : dynamicGapThreshold;
  final segments = <WaterHistorySegment>[];
  var current = <WaterLevel>[series.first];
  for (var index = 1; index < series.length; index++) {
    final gap = series[index].timestamp.difference(series[index - 1].timestamp);
    if (gap > gapThreshold) {
      segments.add(WaterHistorySegment(List<WaterLevel>.unmodifiable(current)));
      current = <WaterLevel>[];
    }
    current.add(series[index]);
  }
  segments.add(WaterHistorySegment(List<WaterLevel>.unmodifiable(current)));
  return WaterTrendHistory(
    realObservations: List<WaterLevel>.unmodifiable(series),
    realSegments: List<WaterHistorySegment>.unmodifiable(segments),
    gapThreshold: gapThreshold,
  );
}

bool _observationsAreCompatible(WaterLevel candidate, WaterLevel current) {
  if (_normalizedStationKey(candidate.stationId) !=
          _normalizedStationKey(current.stationId) ||
      candidate.metricCode.trim().toLowerCase() !=
          current.metricCode.trim().toLowerCase() ||
      candidate.unit.trim().toLowerCase() !=
          current.unit.trim().toLowerCase() ||
      candidate.measurementDatum.trim().toLowerCase() !=
          current.measurementDatum.trim().toLowerCase() ||
      candidate.historyContract.trim().toLowerCase() !=
          current.historyContract.trim().toLowerCase() ||
      !_precisionIsCompatible(
        candidate.measurementPrecision,
        current.measurementPrecision,
      )) {
    return false;
  }
  if (candidate.source == current.source) return true;
  return _isOfficialSource(candidate.source) &&
      _isOfficialSource(current.source);
}

bool _precisionIsCompatible(
  WaterMeasurementPrecision candidate,
  WaterMeasurementPrecision current,
) {
  if (candidate == current) return true;
  if (candidate == WaterMeasurementPrecision.unknown ||
      current == WaterMeasurementPrecision.unknown) {
    return true;
  }

  // AFDJ publishes daily observations as date-only, while older canonical
  // fallback observations can carry an exact timestamp. They are still real
  // measurements on the same canonical cm series and are valid chart history.
  // Delta calculation keeps its own stricter date/exact rules, so allowing
  // the pair here does not fabricate a 24h comparison.
  return (candidate == WaterMeasurementPrecision.date &&
          current == WaterMeasurementPrecision.exact) ||
      (candidate == WaterMeasurementPrecision.exact &&
          current == WaterMeasurementPrecision.date);
}

bool _isOfficialSource(WaterLevelSource source) =>
    source != WaterLevelSource.manualFallback;

bool _isValidObservation(WaterLevel reading) =>
    reading.isQualityValid &&
    reading.value.isFinite &&
    reading.timestamp.toUtc().microsecondsSinceEpoch > 0;

WaterDirection _directionForChange(double change, double? resolution) {
  if (!change.isFinite) return WaterDirection.unknown;
  if (_isEffectivelyStable(change, resolution)) return WaterDirection.stable;
  return change > 0 ? WaterDirection.rising : WaterDirection.falling;
}

bool _isEffectivelyStable(double change, double? resolution) {
  final validResolution = _validResolution(resolution);
  return validResolution == null ? change == 0 : change.abs() < validResolution;
}

double? _combinedResolution(WaterLevel first, WaterLevel second) {
  final firstResolution = _validResolution(first.measurementResolution);
  final secondResolution = _validResolution(second.measurementResolution);
  if (firstResolution == null) return secondResolution;
  if (secondResolution == null) return firstResolution;
  return math.max(firstResolution, secondResolution);
}

double? _validResolution(double? value) =>
    value != null && value.isFinite && value > 0 ? value : null;

double _median(List<double> sortedValues) {
  final midpoint = sortedValues.length ~/ 2;
  return sortedValues.length.isOdd
      ? sortedValues[midpoint]
      : (sortedValues[midpoint - 1] + sortedValues[midpoint]) / 2;
}

int _utcCalendarDayDistance(DateTime earlier, DateTime later) {
  final earlierDay = DateTime.utc(
    earlier.toUtc().year,
    earlier.toUtc().month,
    earlier.toUtc().day,
  );
  final laterDay = DateTime.utc(
    later.toUtc().year,
    later.toUtc().month,
    later.toUtc().day,
  );
  return laterDay.difference(earlierDay).inDays;
}

Duration _defaultIntervalTolerance(Duration interval) {
  if (interval <= const Duration(hours: 24)) {
    return canonicalWater24HourTolerance;
  }
  if (interval <= const Duration(hours: 48)) return const Duration(hours: 12);
  return const Duration(hours: 24);
}

String _normalizedStationKey(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[ăâáàä]'), 'a')
    .replaceAll(RegExp('[îíìï]'), 'i')
    .replaceAll(RegExp('[șş]'), 's')
    .replaceAll(RegExp('[țţ]'), 't')
    .replaceAll(RegExp('[^a-z0-9]'), '');
