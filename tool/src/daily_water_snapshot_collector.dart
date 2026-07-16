import 'package:timezone/timezone.dart' as tz;

enum SnapshotSource {
  afdj('AFDJ'),
  danubeHis('DanubeHIS'),
  danubeFis('DanubeFIS');

  const SnapshotSource(this.databaseValue);

  final String databaseValue;
}

enum SnapshotDeltaMethod {
  providerReported('provider_reported'),
  computedSameSource('computed_same_source'),
  unavailable('unavailable');

  const SnapshotDeltaMethod(this.databaseValue);

  final String databaseValue;
}

enum SnapshotQuality {
  valid,
  partial,
  stale,
  providerError,
  unknown;

  String get databaseValue => switch (this) {
    SnapshotQuality.valid => 'valid',
    SnapshotQuality.partial => 'partial',
    SnapshotQuality.stale => 'stale',
    SnapshotQuality.providerError => 'provider_error',
    SnapshotQuality.unknown => 'unknown',
  };
}

class ProviderReading {
  const ProviderReading({
    required this.source,
    required this.levelCm,
    required this.measuredAt,
  });

  final SnapshotSource source;
  final int levelCm;
  final DateTime measuredAt;

  bool get isValid => measuredAt.millisecondsSinceEpoch > 0;
}

class ProviderReportedDelta {
  const ProviderReportedDelta({
    required this.deltaCm,
    required this.source,
    required this.measuredAt,
  });

  final int deltaCm;
  final SnapshotSource source;
  final DateTime measuredAt;
}

class ProviderFailure {
  const ProviderFailure(this.source, this.message);

  final SnapshotSource source;
  final String message;
}

class DailyWaterSnapshotPayload {
  const DailyWaterSnapshotPayload({
    required this.stationId,
    required this.observationDate,
    required this.levelCm,
    required this.levelSource,
    required this.levelMeasuredAt,
    required this.dailyDeltaCm,
    required this.deltaSource,
    required this.deltaMeasuredAt,
    required this.deltaBaseMeasuredAt,
    required this.deltaMethod,
    required this.quality,
  });

  final String stationId;
  final String observationDate;
  final int? levelCm;
  final String? levelSource;
  final DateTime? levelMeasuredAt;
  final int? dailyDeltaCm;
  final String? deltaSource;
  final DateTime? deltaMeasuredAt;
  final DateTime? deltaBaseMeasuredAt;
  final String deltaMethod;
  final String quality;

  Map<String, Object?> toJson() => {
    'station_id': stationId,
    'observation_date': observationDate,
    'level_cm': levelCm,
    'level_source': levelSource,
    'level_measured_at': levelMeasuredAt?.toUtc().toIso8601String(),
    'daily_delta_cm': dailyDeltaCm,
    'delta_source': deltaSource,
    'delta_measured_at': deltaMeasuredAt?.toUtc().toIso8601String(),
    'delta_base_measured_at': deltaBaseMeasuredAt?.toUtc().toIso8601String(),
    'delta_method': deltaMethod,
    'quality': quality,
  };
}

class StationSnapshotResult {
  const StationSnapshotResult({
    required this.stationId,
    required this.stationName,
    required this.payload,
    required this.failures,
  });

  final String stationId;
  final String stationName;
  final DailyWaterSnapshotPayload payload;
  final List<ProviderFailure> failures;
}

class SnapshotRunSummary {
  const SnapshotRunSummary(this.results);

  final List<StationSnapshotResult> results;

  int get totalStations => results.length;
  int get valid => _count(SnapshotQuality.valid);
  int get partial => _count(SnapshotQuality.partial);
  int get stale => _count(SnapshotQuality.stale);
  int get providerError => _count(SnapshotQuality.providerError);
  int get unknown => _count(SnapshotQuality.unknown);
  int get withoutDelta => results
      .where((result) => result.payload.deltaMethod == 'unavailable')
      .length;

  int _count(SnapshotQuality quality) => results
      .where((result) => result.payload.quality == quality.databaseValue)
      .length;
}

class DailyWaterSnapshotBuilder {
  const DailyWaterSnapshotBuilder({
    this.freshnessThreshold = const Duration(hours: 36),
  });

  final Duration freshnessThreshold;

  DailyWaterSnapshotPayload build({
    required String stationId,
    required DateTime nowUtc,
    required Iterable<ProviderReading> readings,
    Iterable<ProviderReportedDelta> reportedDeltas = const [],
    Iterable<ProviderFailure> failures = const [],
  }) {
    final normalizedNow = nowUtc.toUtc();
    final validReadings = readings.where((reading) => reading.isValid).toList()
      ..sort(_compareReadings);
    final selectedLevel = _selectLevel(validReadings, normalizedNow);
    final delta = _selectDelta(validReadings, reportedDeltas);
    final quality = _qualityFor(
      selectedLevel: selectedLevel,
      delta: delta,
      failures: failures,
      nowUtc: normalizedNow,
    );

    return DailyWaterSnapshotPayload(
      stationId: stationId,
      observationDate: observationDateFor(normalizedNow),
      levelCm: selectedLevel?.levelCm,
      levelSource: selectedLevel?.source.databaseValue,
      levelMeasuredAt: selectedLevel?.measuredAt,
      dailyDeltaCm: delta.value,
      deltaSource: delta.source?.databaseValue,
      deltaMeasuredAt: delta.measuredAt,
      deltaBaseMeasuredAt: delta.baseMeasuredAt,
      deltaMethod: delta.method.databaseValue,
      quality: quality.databaseValue,
    );
  }

  static String observationDateFor(DateTime nowUtc) {
    final local = tz.TZDateTime.from(
      nowUtc.toUtc(),
      tz.getLocation('Europe/Bucharest'),
    );
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  ProviderReading? _selectLevel(
    List<ProviderReading> readings,
    DateTime nowUtc,
  ) {
    if (readings.isEmpty) return null;
    final freshAfdj = readings.where(
      (reading) =>
          reading.source == SnapshotSource.afdj &&
          _isFresh(reading.measuredAt, nowUtc),
    );
    return (freshAfdj.isNotEmpty ? freshAfdj : readings).first;
  }

  _DeltaSelection _selectDelta(
    List<ProviderReading> readings,
    Iterable<ProviderReportedDelta> reportedDeltas,
  ) {
    final reported = reportedDeltas.toList()
      ..sort((a, b) {
        final time = b.measuredAt.toUtc().compareTo(a.measuredAt.toUtc());
        return time != 0 ? time : a.source.index.compareTo(b.source.index);
      });
    if (reported.isNotEmpty) {
      final value = reported.first;
      return _DeltaSelection.reported(value);
    }

    final candidates = <_DeltaSelection>[];
    for (final source in SnapshotSource.values) {
      final sourceReadings =
          readings.where((reading) => reading.source == source).toList()..sort(
            (a, b) => a.measuredAt.toUtc().compareTo(b.measuredAt.toUtc()),
          );
      if (sourceReadings.length < 2) continue;
      final base = sourceReadings[sourceReadings.length - 2];
      final current = sourceReadings.last;
      if (!base.measuredAt.toUtc().isBefore(current.measuredAt.toUtc())) {
        continue;
      }
      candidates.add(_DeltaSelection.computed(current, base));
    }
    if (candidates.isEmpty) return const _DeltaSelection.unavailable();
    candidates.sort((a, b) {
      final time = b.measuredAt!.toUtc().compareTo(a.measuredAt!.toUtc());
      return time != 0 ? time : a.source!.index.compareTo(b.source!.index);
    });
    return candidates.first;
  }

  SnapshotQuality _qualityFor({
    required ProviderReading? selectedLevel,
    required _DeltaSelection delta,
    required Iterable<ProviderFailure> failures,
    required DateTime nowUtc,
  }) {
    if (selectedLevel == null) {
      return failures.isNotEmpty
          ? SnapshotQuality.providerError
          : SnapshotQuality.unknown;
    }
    if (!_isFresh(selectedLevel.measuredAt, nowUtc)) {
      return SnapshotQuality.stale;
    }
    return delta.method == SnapshotDeltaMethod.unavailable
        ? SnapshotQuality.partial
        : SnapshotQuality.valid;
  }

  bool _isFresh(DateTime measuredAt, DateTime nowUtc) {
    final age = nowUtc.difference(measuredAt.toUtc());
    return age >= const Duration(minutes: -5) && age <= freshnessThreshold;
  }

  static int _compareReadings(ProviderReading a, ProviderReading b) {
    final time = b.measuredAt.toUtc().compareTo(a.measuredAt.toUtc());
    if (time != 0) return time;
    final source = a.source.index.compareTo(b.source.index);
    if (source != 0) return source;
    return a.levelCm.compareTo(b.levelCm);
  }
}

enum DailyWaterSnapshotMergeOutcome {
  identicalNoOp,
  improvedUpdate,
  conflictRefused,
}

class DailyWaterSnapshotMergeResult {
  const DailyWaterSnapshotMergeResult._({
    required this.outcome,
    required this.payload,
    this.conflictingFields = const [],
  });

  const DailyWaterSnapshotMergeResult.identicalNoOp(
    DailyWaterSnapshotPayload payload,
  ) : this._(
        outcome: DailyWaterSnapshotMergeOutcome.identicalNoOp,
        payload: payload,
      );

  const DailyWaterSnapshotMergeResult.improvedUpdate(
    DailyWaterSnapshotPayload payload,
  ) : this._(
        outcome: DailyWaterSnapshotMergeOutcome.improvedUpdate,
        payload: payload,
      );

  const DailyWaterSnapshotMergeResult.conflictRefused({
    required DailyWaterSnapshotPayload payload,
    required List<String> conflictingFields,
  }) : this._(
         outcome: DailyWaterSnapshotMergeOutcome.conflictRefused,
         payload: payload,
         conflictingFields: conflictingFields,
       );

  final DailyWaterSnapshotMergeOutcome outcome;
  final DailyWaterSnapshotPayload payload;
  final List<String> conflictingFields;
}

/// Merges compatible same-day snapshots without combining fields from distinct
/// level or delta observations. It is deliberately independent of provider
/// ordering and has no side effects.
class DailyWaterSnapshotMerger {
  const DailyWaterSnapshotMerger();

  DailyWaterSnapshotMergeResult merge({
    required DailyWaterSnapshotPayload existing,
    required DailyWaterSnapshotPayload incoming,
    required DateTime nowUtc,
  }) {
    final immutableConflicts = <String>[];
    if (existing.stationId != incoming.stationId) {
      immutableConflicts.add('station_id');
    }
    if (existing.observationDate != incoming.observationDate) {
      immutableConflicts.add('observation_date');
    }
    if (immutableConflicts.isNotEmpty) {
      return DailyWaterSnapshotMergeResult.conflictRefused(
        payload: existing,
        conflictingFields: immutableConflicts,
      );
    }

    final level = _mergeLevel(existing, incoming);
    if (level.conflict) {
      return DailyWaterSnapshotMergeResult.conflictRefused(
        payload: existing,
        conflictingFields: const [
          'level_cm',
          'level_source',
          'level_measured_at',
        ],
      );
    }
    final delta = _mergeDelta(existing, incoming);
    if (delta.conflict) {
      return DailyWaterSnapshotMergeResult.conflictRefused(
        payload: existing,
        conflictingFields: const [
          'daily_delta_cm',
          'delta_source',
          'delta_measured_at',
          'delta_base_measured_at',
          'delta_method',
        ],
      );
    }
    if (!level.changed && !delta.changed) {
      return DailyWaterSnapshotMergeResult.identicalNoOp(existing);
    }

    final merged = DailyWaterSnapshotPayload(
      stationId: existing.stationId,
      observationDate: existing.observationDate,
      levelCm: level.payload.levelCm,
      levelSource: level.payload.levelSource,
      levelMeasuredAt: level.payload.levelMeasuredAt,
      dailyDeltaCm: delta.payload.dailyDeltaCm,
      deltaSource: delta.payload.deltaSource,
      deltaMeasuredAt: delta.payload.deltaMeasuredAt,
      deltaBaseMeasuredAt: delta.payload.deltaBaseMeasuredAt,
      deltaMethod: delta.payload.deltaMethod,
      quality: _recalculateQuality(
        level: level.payload,
        delta: delta.payload,
        existing: existing,
        incoming: incoming,
        nowUtc: nowUtc,
      ),
    );
    return DailyWaterSnapshotMergeResult.improvedUpdate(merged);
  }

  _MergeGroup _mergeLevel(
    DailyWaterSnapshotPayload existing,
    DailyWaterSnapshotPayload incoming,
  ) {
    final existingComplete = existing.levelCm != null;
    final incomingComplete = incoming.levelCm != null;
    if (!existingComplete || !incomingComplete) {
      return _MergeGroup(
        payload: incomingComplete ? incoming : existing,
        changed: !existingComplete && incomingComplete,
      );
    }
    final time = incoming.levelMeasuredAt!.toUtc().compareTo(
      existing.levelMeasuredAt!.toUtc(),
    );
    if (time > 0) return _MergeGroup(payload: incoming, changed: true);
    if (time < 0) return _MergeGroup(payload: existing, changed: false);
    if (_sameLevel(existing, incoming)) {
      return _MergeGroup(payload: existing, changed: false);
    }
    return _MergeGroup(payload: existing, conflict: true);
  }

  _MergeGroup _mergeDelta(
    DailyWaterSnapshotPayload existing,
    DailyWaterSnapshotPayload incoming,
  ) {
    final existingRank = _deltaRank(existing.deltaMethod);
    final incomingRank = _deltaRank(incoming.deltaMethod);
    if (incomingRank > existingRank) {
      return _MergeGroup(payload: incoming, changed: true);
    }
    if (incomingRank < existingRank) {
      return _MergeGroup(payload: existing, changed: false);
    }
    if (incomingRank == 0) {
      return _MergeGroup(payload: existing, changed: false);
    }
    final time = incoming.deltaMeasuredAt!.toUtc().compareTo(
      existing.deltaMeasuredAt!.toUtc(),
    );
    if (time > 0) return _MergeGroup(payload: incoming, changed: true);
    if (time < 0) return _MergeGroup(payload: existing, changed: false);
    if (_sameDelta(existing, incoming)) {
      return _MergeGroup(payload: existing, changed: false);
    }
    return _MergeGroup(payload: existing, conflict: true);
  }

  String _recalculateQuality({
    required DailyWaterSnapshotPayload level,
    required DailyWaterSnapshotPayload delta,
    required DailyWaterSnapshotPayload existing,
    required DailyWaterSnapshotPayload incoming,
    required DateTime nowUtc,
  }) {
    final source = SnapshotSource.values.firstWhere(
      (source) => source.databaseValue == level.levelSource,
      orElse: () => SnapshotSource.afdj,
    );
    final selectedLevel = level.levelCm == null
        ? null
        : ProviderReading(
            source: source,
            levelCm: level.levelCm!,
            measuredAt: level.levelMeasuredAt!,
          );
    final deltaSelection = delta.deltaMethod == 'unavailable'
        ? const _DeltaSelection.unavailable()
        : _DeltaSelection._(
            value: delta.dailyDeltaCm,
            source: null,
            measuredAt: delta.deltaMeasuredAt,
            baseMeasuredAt: delta.deltaBaseMeasuredAt,
            method: SnapshotDeltaMethod.values.firstWhere(
              (method) => method.databaseValue == delta.deltaMethod,
            ),
          );
    final hadProviderFailure =
        existing.quality == SnapshotQuality.providerError.databaseValue ||
        incoming.quality == SnapshotQuality.providerError.databaseValue;
    return const DailyWaterSnapshotBuilder()
        ._qualityFor(
          selectedLevel: selectedLevel,
          delta: deltaSelection,
          failures: hadProviderFailure
              ? const [ProviderFailure(SnapshotSource.afdj, 'provider error')]
              : const [],
          nowUtc: nowUtc.toUtc(),
        )
        .databaseValue;
  }

  static int _deltaRank(String method) => switch (method) {
    'provider_reported' => 2,
    'computed_same_source' => 1,
    _ => 0,
  };

  static bool _sameLevel(
    DailyWaterSnapshotPayload a,
    DailyWaterSnapshotPayload b,
  ) =>
      a.levelCm == b.levelCm &&
      a.levelSource == b.levelSource &&
      _sameTime(a.levelMeasuredAt, b.levelMeasuredAt);

  static bool _sameDelta(
    DailyWaterSnapshotPayload a,
    DailyWaterSnapshotPayload b,
  ) =>
      a.dailyDeltaCm == b.dailyDeltaCm &&
      a.deltaSource == b.deltaSource &&
      _sameTime(a.deltaMeasuredAt, b.deltaMeasuredAt) &&
      _sameTime(a.deltaBaseMeasuredAt, b.deltaBaseMeasuredAt) &&
      a.deltaMethod == b.deltaMethod;

  static bool _sameTime(DateTime? a, DateTime? b) =>
      a?.toUtc().millisecondsSinceEpoch == b?.toUtc().millisecondsSinceEpoch;
}

class _MergeGroup {
  const _MergeGroup({
    required this.payload,
    this.changed = false,
    this.conflict = false,
  });

  final DailyWaterSnapshotPayload payload;
  final bool changed;
  final bool conflict;
}

class _DeltaSelection {
  const _DeltaSelection._({
    required this.value,
    required this.source,
    required this.measuredAt,
    required this.baseMeasuredAt,
    required this.method,
  });

  const _DeltaSelection.unavailable()
    : value = null,
      source = null,
      measuredAt = null,
      baseMeasuredAt = null,
      method = SnapshotDeltaMethod.unavailable;

  factory _DeltaSelection.reported(ProviderReportedDelta value) =>
      _DeltaSelection._(
        value: value.deltaCm,
        source: value.source,
        measuredAt: value.measuredAt,
        baseMeasuredAt: null,
        method: SnapshotDeltaMethod.providerReported,
      );

  factory _DeltaSelection.computed(
    ProviderReading current,
    ProviderReading base,
  ) => _DeltaSelection._(
    value: current.levelCm - base.levelCm,
    source: current.source,
    measuredAt: current.measuredAt,
    baseMeasuredAt: base.measuredAt,
    method: SnapshotDeltaMethod.computedSameSource,
  );

  final int? value;
  final SnapshotSource? source;
  final DateTime? measuredAt;
  final DateTime? baseMeasuredAt;
  final SnapshotDeltaMethod method;
}
