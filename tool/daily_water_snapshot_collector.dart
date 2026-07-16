import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart';

import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/afdj_water_provider.dart';
import 'package:fishtrack/repositories/danube_fis_water_provider.dart';
import 'package:fishtrack/repositories/danube_his_water_provider.dart';
import 'src/daily_water_snapshot_collector.dart';
import 'src/daily_water_snapshot_supabase_writer.dart';

/// Canonical Romanian Danube roster from WaterRepository. Periprava is not an
/// accepted station and is intentionally absent. IDs follow the established
/// collector convention (`bazias`) and are verified by the writer before any
/// snapshot write.
const canonicalWaterStations = <String, String>{
  'bazias': 'Baziaș',
  'moldova_veche': 'Moldova Veche',
  'drencova': 'Drencova',
  'orsova': 'Orsova',
  'drobeta_turnu_severin': 'Drobeta Turnu Severin',
  'gruia': 'Gruia',
  'cetate': 'Cetate',
  'calafat': 'Calafat',
  'rast': 'Rast',
  'bechet': 'Bechet',
  'corabia': 'Corabia',
  'turnu_magurele': 'Turnu Magurele',
  'zimnicea': 'Zimnicea',
  'giurgiu': 'Giurgiu',
  'oltenita': 'Oltenita',
  'calarasi': 'Calarasi',
  'cernavoda': 'Cernavoda',
  'harsova': 'Harsova',
  'braila': 'Braila',
  'galati': 'Galati',
  'isaccea': 'Isaccea',
  'tulcea': 'Tulcea',
  'sulina': 'Sulina',
};

/// Supabase station IDs for canonical stations that are represented by the
/// metadata fallback in WaterRepository. The CLI IDs remain canonical so that
/// collection and reporting cannot confuse these stations with their aliases.
const canonicalRemoteStationIds = <String, String>{
  'drencova': 'afdj-drencova',
  'gruia': 'afdj-gruia',
  'cetate': 'afdj-cetate',
  'rast': 'afdj-rast',
};

typedef SnapshotCollector =
    Future<StationSnapshotResult> Function(
      String stationId,
      String stationName,
    );
typedef SnapshotWriterFactory =
    DailyWaterSnapshotWriter Function(String supabaseUrl, String secretKey);

Future<void> main(List<String> arguments) async {
  initializeTimeZones();
  final command = DailyWaterSnapshotCommand(
    stations: canonicalWaterStations,
    remoteStationIds: canonicalRemoteStationIds,
    collect: _collect,
    writerFactory: (url, key) => SupabaseDailyWaterSnapshotWriter(
      supabaseUrl: url,
      secretKey: key,
      client: http.Client(),
    ),
    environment: Platform.environment,
    output: stdout.writeln,
    error: stderr.writeln,
  );
  exitCode = await command.run(arguments);
}

class DailyWaterSnapshotCommand {
  DailyWaterSnapshotCommand({
    required this.stations,
    this.remoteStationIds = const {},
    required this.collect,
    required this.writerFactory,
    required this.environment,
    required this.output,
    required this.error,
  });

  final Map<String, String> stations;
  final Map<String, String> remoteStationIds;
  final SnapshotCollector collect;
  final SnapshotWriterFactory writerFactory;
  final Map<String, String> environment;
  final void Function(String message) output;
  final void Function(String message) error;

  Future<int> run(List<String> arguments) async {
    if (arguments.contains('--help')) {
      output(
        'Usage: dart run tool/daily_water_snapshot_collector.dart '
        '--station-id=bazias [--dry-run] | --all-stations --dry-run; '
        'apply requires one --confirm-station-id for each selected station.',
      );
      return 0;
    }
    if (!_hasOnlySupportedArguments(arguments)) {
      error(
        'Unsupported argument. Secrets are accepted only through environment variables.',
      );
      return 64;
    }

    final apply = arguments.contains('--apply');
    final allStations = arguments.contains('--all-stations');
    final stationIds = _argumentValues(arguments, '--station-id=');
    final selectedStationIds = _selectStationIds(
      allStations: allStations,
      stationIds: stationIds,
    );
    if (selectedStationIds == null) {
      error(
        'Select one or more known --station-id values (for example '
        '--station-id=bazias) or use --all-stations explicitly.',
      );
      return 64;
    }
    if (!apply) return _runBatch(selectedStationIds);

    final confirmations = _argumentValues(arguments, '--confirm-station-id=');
    if (!_hasExactConfirmations(selectedStationIds, confirmations)) {
      error(
        'Apply requires one matching --confirm-station-id for each selected station.',
      );
      return 64;
    }

    final supabaseUrl = environment['SUPABASE_URL'];
    if (supabaseUrl == null || !_isValidSupabaseUrl(supabaseUrl)) {
      error(
        'Apply requires SUPABASE_URL to be an HTTPS Supabase base URL without whitespace or /rest/v1.',
      );
      return 64;
    }
    final secretKey = environment['SUPABASE_SECRET_KEY'];
    if (secretKey == null || secretKey.trim().isEmpty) {
      error('Apply requires SUPABASE_SECRET_KEY in the environment.');
      return 64;
    }

    final writer = writerFactory(supabaseUrl, secretKey);
    try {
      return await _runBatch(selectedStationIds, writer: writer);
    } finally {
      writer.close();
    }
  }

  Future<int> _runBatch(
    List<String> stationIds, {
    DailyWaterSnapshotWriter? writer,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final outcomes = <_StationRunOutcome>[];
    final sources = <String>{};

    for (final stationId in stationIds) {
      final stationName = stations[stationId]!;
      final remoteStationId = remoteStationIds[stationId] ?? stationId;
      try {
        final result = await collect(remoteStationId, stationName);
        final validationError = _validationError(
          result,
          expectedStationId: remoteStationId,
          expectedStationName: stationName,
        );
        if (validationError != null) {
          outcomes.add(_StationRunOutcome.skipped(stationId, validationError));
          output(
            'station_id=$stationId; remote_station_id=$remoteStationId; '
            'skipped: $validationError',
          );
          continue;
        }

        final source = result.payload.levelSource!;
        sources.add(source);
        if (writer == null) {
          outcomes.add(_StationRunOutcome.fetched(stationId));
          output(
            'station_id=$stationId; remote_station_id=$remoteStationId; '
            'fetched; source=$source; level_cm=${result.payload.levelCm}; '
            'observation_date=${result.payload.observationDate}',
          );
          continue;
        }

        final writeResult = await writer.writeIfAbsent(result.payload);
        switch (writeResult.outcome) {
          case SnapshotWriteOutcome.inserted:
            outcomes.add(_StationRunOutcome.inserted(stationId));
            output(
              'station_id=$stationId; remote_station_id=$remoteStationId; '
              'inserted; source=$source; level_cm=${result.payload.levelCm}; '
              'observation_date=${result.payload.observationDate}',
            );
          case SnapshotWriteOutcome.updated:
            outcomes.add(_StationRunOutcome.updated(stationId));
            output(
              'station_id=$stationId; remote_station_id=$remoteStationId; '
              'updated; source=$source; level_cm=${result.payload.levelCm}; '
              'observation_date=${result.payload.observationDate}',
            );
          case SnapshotWriteOutcome.alreadyExists:
            outcomes.add(_StationRunOutcome.unchanged(stationId));
            output(
              'station_id=$stationId; remote_station_id=$remoteStationId; '
              'unchanged; source=$source; level_cm=${result.payload.levelCm}; '
              'observation_date=${result.payload.observationDate}',
            );
        }
      } on SnapshotWriteException catch (exception) {
        final message = _safeError(exception);
        outcomes.add(_StationRunOutcome.failed(stationId, message));
        error('station_id=$stationId; $message');
      } on Object catch (exception) {
        final message = _safeError(exception);
        outcomes.add(_StationRunOutcome.failed(stationId, message));
        error('station_id=$stationId; $message');
      }
    }

    final summary = _BatchRunSummary(
      totalStations: stationIds.length,
      outcomes: outcomes,
      sources: sources,
      elapsed: DateTime.now().toUtc().difference(startedAt),
    );
    _printBatchSummary(summary, output);
    for (final failed in summary.failedStations) {
      output('failed station: ${failed.stationId}; ${failed.reason}');
    }
    return summary.hasFailures ? 1 : 0;
  }

  List<String>? _selectStationIds({
    required bool allStations,
    required List<String> stationIds,
  }) {
    if (allStations) {
      if (stationIds.isNotEmpty) return null;
      return stations.keys.toList(growable: false);
    }
    if (stationIds.isEmpty ||
        stationIds.toSet().length != stationIds.length ||
        stationIds.any((stationId) => !stations.containsKey(stationId))) {
      return null;
    }
    return stationIds;
  }

  static bool _hasExactConfirmations(
    List<String> stationIds,
    List<String> confirmations,
  ) =>
      stationIds.length == confirmations.length &&
      stationIds.toSet().containsAll(confirmations) &&
      confirmations.toSet().containsAll(stationIds);

  static List<String> _argumentValues(List<String> arguments, String prefix) =>
      arguments
          .where((argument) => argument.startsWith(prefix))
          .map((argument) => argument.substring(prefix.length))
          .toList(growable: false);

  static bool _hasOnlySupportedArguments(List<String> arguments) =>
      arguments.every(
        (argument) =>
            argument == '--apply' ||
            argument == '--dry-run' ||
            argument == '--all-stations' ||
            argument.startsWith('--station-id=') ||
            argument.startsWith('--confirm-station-id='),
      );

  static bool _isValidSupabaseUrl(String value) =>
      RegExp(r'^https://[A-Za-z0-9-]+\.supabase\.co$').hasMatch(value);
}

String? _validationError(
  StationSnapshotResult result, {
  required String expectedStationId,
  required String expectedStationName,
}) {
  final payload = result.payload;
  if (result.stationId != expectedStationId ||
      payload.stationId != expectedStationId ||
      result.stationName != expectedStationName) {
    return 'station identity mismatch';
  }
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(payload.observationDate) ||
      DateTime.tryParse('${payload.observationDate}T00:00:00Z') == null) {
    return 'invalid observation date';
  }
  final level = payload.levelCm;
  if (level == null) return 'missing numeric level';
  if (level < -1000 || level > 5000) return 'impossible level_cm=$level';
  final source = payload.levelSource;
  if (source == null ||
      !SnapshotSource.values.any((value) => value.databaseValue == source)) {
    return 'missing or invalid level source';
  }
  final measuredAt = payload.levelMeasuredAt?.toUtc();
  if (measuredAt == null || measuredAt.millisecondsSinceEpoch <= 0) {
    return 'invalid level timestamp';
  }
  if (measuredAt.isAfter(
    DateTime.now().toUtc().add(const Duration(minutes: 5)),
  )) {
    return 'future level timestamp';
  }
  return null;
}

enum _StationRunKind { fetched, inserted, updated, unchanged, skipped, failed }

class _StationRunOutcome {
  const _StationRunOutcome._(this.stationId, this.kind, [this.reason]);

  const _StationRunOutcome.fetched(String stationId)
    : this._(stationId, _StationRunKind.fetched);
  const _StationRunOutcome.inserted(String stationId)
    : this._(stationId, _StationRunKind.inserted);
  const _StationRunOutcome.updated(String stationId)
    : this._(stationId, _StationRunKind.updated);
  const _StationRunOutcome.unchanged(String stationId)
    : this._(stationId, _StationRunKind.unchanged);
  const _StationRunOutcome.skipped(String stationId, String reason)
    : this._(stationId, _StationRunKind.skipped, reason);
  const _StationRunOutcome.failed(String stationId, String reason)
    : this._(stationId, _StationRunKind.failed, reason);

  final String stationId;
  final _StationRunKind kind;
  final String? reason;
}

class _BatchRunSummary {
  const _BatchRunSummary({
    required this.totalStations,
    required this.outcomes,
    required this.sources,
    required this.elapsed,
  });

  final int totalStations;
  final List<_StationRunOutcome> outcomes;
  final Set<String> sources;
  final Duration elapsed;

  int get fetched => _count(_StationRunKind.fetched);
  int get inserted => _count(_StationRunKind.inserted);
  int get updated => _count(_StationRunKind.updated);
  int get unchanged => _count(_StationRunKind.unchanged);
  int get skipped => _count(_StationRunKind.skipped);
  int get failed => _count(_StationRunKind.failed);
  bool get hasFailures => skipped > 0 || failed > 0;
  List<_StationRunOutcome> get failedStations => outcomes
      .where((outcome) => outcome.kind == _StationRunKind.failed)
      .toList(growable: false);

  int _count(_StationRunKind kind) =>
      outcomes.where((outcome) => outcome.kind == kind).length;

  String get result => failed == totalStations
      ? 'total_failure'
      : hasFailures
      ? 'partial_success'
      : 'complete_success';
}

Future<StationSnapshotResult> _collect(
  String stationId,
  String stationName,
) async {
  const afdj = AfdjWaterProvider();
  const fis = DanubeFisWaterProvider();
  const his = DanubeHisWaterProvider();
  final readings = <ProviderReading>[];
  final failures = <ProviderFailure>[];

  await _readProvider(
    source: SnapshotSource.afdj,
    load: () => afdj.getLevels([stationName]),
    stationName: stationName,
    stationId: stationId,
    readings: readings,
    failures: failures,
  );
  await _readProvider(
    source: SnapshotSource.danubeFis,
    load: () => fis.getLevels([stationName]),
    stationName: stationName,
    stationId: stationId,
    readings: readings,
    failures: failures,
  );
  await _readProvider(
    source: SnapshotSource.danubeHis,
    load: () => his.getLevels([stationName], limit: 14),
    stationName: stationName,
    stationId: stationId,
    readings: readings,
    failures: failures,
  );

  final payload = const DailyWaterSnapshotBuilder().build(
    stationId: stationId,
    nowUtc: DateTime.now().toUtc(),
    readings: readings,
    failures: failures,
  );
  return StationSnapshotResult(
    stationId: stationId,
    stationName: stationName,
    payload: payload,
    failures: failures,
  );
}

Future<void> _readProvider({
  required SnapshotSource source,
  required Future<Map<String, List<WaterLevel>>> Function() load,
  required String stationName,
  required String stationId,
  required List<ProviderReading> readings,
  required List<ProviderFailure> failures,
}) async {
  try {
    final levels = (await load()).values.expand((value) => value);
    for (final level in levels) {
      final rounded = level.value.round();
      if (!level.value.isFinite || level.value != rounded) continue;
      readings.add(
        ProviderReading(
          source: source,
          levelCm: rounded,
          measuredAt: level.timestamp,
        ),
      );
    }
  } on Object catch (error) {
    failures.add(ProviderFailure(source, _safeError(error)));
  }
}

String _safeError(Object error) {
  final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 160 ? text : '${text.substring(0, 160)}…';
}

void _printBatchSummary(
  _BatchRunSummary summary,
  void Function(String) output,
) {
  final sources = summary.sources.isEmpty
      ? 'none'
      : (summary.sources.toList()..sort()).join(',');
  output(
    'batch summary: result=${summary.result}; '
    'total stations=${summary.totalStations}; fetched=${summary.fetched}; '
    'inserted=${summary.inserted}; updated=${summary.updated}; '
    'unchanged=${summary.unchanged}; skipped=${summary.skipped}; '
    'failed=${summary.failed}; duration_ms=${summary.elapsed.inMilliseconds}; '
    'sources=$sources',
  );
}
