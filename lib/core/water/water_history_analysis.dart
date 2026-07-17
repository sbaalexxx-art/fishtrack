import '../../models/station.dart';
import '../../models/water_level.dart';

const double waterStableDeltaThresholdCm = .01;

List<WaterLevel> realWaterHistorySeries(
  List<WaterLevel> history, {
  required Duration period,
  String? stationId,
}) {
  final expectedStation = stationId == null
      ? null
      : _normalizedStationKey(stationId);
  final valid =
      history
          .where((reading) {
            if (!reading.value.isFinite ||
                reading.timestamp.millisecondsSinceEpoch <= 0) {
              return false;
            }
            if (expectedStation == null) return true;
            return _normalizedStationKey(reading.stationId) == expectedStation;
          })
          .toList(growable: false)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (valid.isEmpty) return const <WaterLevel>[];

  final cutoff = valid.last.timestamp.subtract(period);
  final byObservation = <int, WaterLevel>{};
  for (final reading in valid) {
    if (reading.timestamp.isBefore(cutoff)) continue;
    byObservation[reading.timestamp.toUtc().microsecondsSinceEpoch] = reading;
  }
  final result = byObservation.values.toList(growable: false)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return List<WaterLevel>.unmodifiable(result);
}

WaterTrend? waterTrendFromRealDelta(double? deltaCm) {
  if (deltaCm == null || !deltaCm.isFinite) return null;
  if (deltaCm.abs() <= waterStableDeltaThresholdCm) {
    return WaterTrend.stable;
  }
  return deltaCm > 0 ? WaterTrend.rising : WaterTrend.falling;
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

  WaterTrend get trend => waterTrendFromRealDelta(deltaCm)!;
}

WaterIntervalDelta? realWaterIntervalDelta(
  List<WaterLevel> history,
  Duration targetInterval, {
  String? stationId,
  Duration? tolerance,
}) {
  final series = realWaterHistorySeries(
    history,
    period:
        targetInterval +
        (tolerance ?? _defaultIntervalTolerance(targetInterval)),
    stationId: stationId,
  );
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

Duration _defaultIntervalTolerance(Duration interval) {
  if (interval <= const Duration(hours: 24)) return const Duration(hours: 6);
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
