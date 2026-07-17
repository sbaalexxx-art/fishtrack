import 'package:timezone/timezone.dart' as tz;

import 'daily_water_snapshot_collector.dart';

/// Builds database-ready daily snapshots only from real provider observations.
///
/// If a provider exposes multiple observations for the same Bucharest calendar
/// day, the newest real observation wins. A source is used only as a stable
/// tie-breaker when timestamps are identical. Missing days stay missing.
class RealWaterHistoryBackfillBuilder {
  const RealWaterHistoryBackfillBuilder();

  List<DailyWaterSnapshotPayload> build({
    required String stationId,
    required DateTime nowUtc,
    required int days,
    required Iterable<ProviderReading> readings,
  }) {
    if (stationId.trim().isEmpty || days < 1 || days > 30) {
      return const <DailyWaterSnapshotPayload>[];
    }

    final normalizedNow = nowUtc.toUtc();
    final endDate = DailyWaterSnapshotBuilder.observationDateFor(normalizedNow);
    final localNow = _bucharestDate(normalizedNow);
    final startDate = _observationDate(
      tz.TZDateTime(
        localNow.location,
        localNow.year,
        localNow.month,
        localNow.day - (days - 1),
      ),
    );
    final selectedByDate = <String, ProviderReading>{};

    for (final reading in readings) {
      if (!reading.isValid ||
          reading.measuredAt.toUtc().isAfter(
            normalizedNow.add(const Duration(minutes: 5)),
          )) {
        continue;
      }
      final observationDate = DailyWaterSnapshotBuilder.observationDateFor(
        reading.measuredAt,
      );
      if (observationDate.compareTo(startDate) < 0 ||
          observationDate.compareTo(endDate) > 0) {
        continue;
      }
      final existing = selectedByDate[observationDate];
      if (existing == null || _isPreferred(reading, existing)) {
        selectedByDate[observationDate] = reading;
      }
    }

    final dates = selectedByDate.keys.toList()..sort();
    ProviderReading? previous;
    return dates
        .map((date) {
          final reading = selectedByDate[date]!;
          final compatiblePrevious = previous?.source == reading.source
              ? previous
              : null;
          final payload = DailyWaterSnapshotPayload(
            stationId: stationId,
            observationDate: date,
            levelCm: reading.levelCm,
            levelSource: reading.source.databaseValue,
            levelMeasuredAt: reading.measuredAt.toUtc(),
            dailyDeltaCm: compatiblePrevious == null
                ? null
                : reading.levelCm - compatiblePrevious.levelCm,
            deltaSource: compatiblePrevious == null
                ? null
                : reading.source.databaseValue,
            deltaMeasuredAt: compatiblePrevious == null
                ? null
                : reading.measuredAt.toUtc(),
            deltaBaseMeasuredAt: compatiblePrevious?.measuredAt.toUtc(),
            deltaMethod: compatiblePrevious == null
                ? SnapshotDeltaMethod.unavailable.databaseValue
                : SnapshotDeltaMethod.computedSameSource.databaseValue,
            quality: compatiblePrevious == null
                ? SnapshotQuality.partial.databaseValue
                : SnapshotQuality.valid.databaseValue,
          );
          previous = reading;
          return payload;
        })
        .toList(growable: false);
  }

  static bool _isPreferred(ProviderReading candidate, ProviderReading current) {
    final authority = candidate.source.authorityRank.compareTo(
      current.source.authorityRank,
    );
    if (authority != 0) return authority > 0;
    final timestamp = candidate.measuredAt.toUtc().compareTo(
      current.measuredAt.toUtc(),
    );
    if (timestamp != 0) return timestamp > 0;
    // Conflicting real values with the same source and timestamp are reduced
    // canonically so provider iteration order cannot change the plan.
    return candidate.levelCm < current.levelCm;
  }

  static tz.TZDateTime _bucharestDate(DateTime value) =>
      tz.TZDateTime.from(value.toUtc(), tz.getLocation('Europe/Bucharest'));

  static String _observationDate(tz.TZDateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
