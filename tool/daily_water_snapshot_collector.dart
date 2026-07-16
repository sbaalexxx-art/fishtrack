import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart';

import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/afdj_water_provider.dart';
import 'package:fishtrack/repositories/danube_fis_water_provider.dart';
import 'package:fishtrack/repositories/danube_his_water_provider.dart';
import 'src/daily_water_snapshot_collector.dart';
import 'src/daily_water_snapshot_supabase_writer.dart';

const _stations = <String, String>{'bazias': 'Baziaș'};

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
    stations: _stations,
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
    required this.collect,
    required this.writerFactory,
    required this.environment,
    required this.output,
    required this.error,
  });

  final Map<String, String> stations;
  final SnapshotCollector collect;
  final SnapshotWriterFactory writerFactory;
  final Map<String, String> environment;
  final void Function(String message) output;
  final void Function(String message) error;

  Future<int> run(List<String> arguments) async {
    if (arguments.contains('--help')) {
      output(
        'Usage: dart run tool/daily_water_snapshot_collector.dart '
        '--station-id=bazias [--dry-run] '
        '[--apply --confirm-station-id=bazias]',
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
    final stationIds = _argumentValues(arguments, '--station-id=');
    if (!apply) return _runDryRun(stationIds);

    final confirmations = _argumentValues(arguments, '--confirm-station-id=');
    if (stationIds.length != 1 || stationIds.single != 'bazias') {
      error('Apply requires exactly one --station-id=bazias.');
      return 64;
    }
    if (confirmations.length != 1) {
      error('Apply requires --confirm-station-id=bazias.');
      return 64;
    }
    if (confirmations.single != stationIds.single) {
      error('Confirmation must match --station-id exactly.');
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

    final result = await collect(
      stationIds.single,
      stations[stationIds.single]!,
    );
    _printResult(result, output);
    _printSummary(SnapshotRunSummary([result]), output);
    output('LIVE WRITE: daily_water_snapshots');
    output('Station: ${result.stationId}');
    output('Observation date: ${result.payload.observationDate}');

    final writer = writerFactory(supabaseUrl, secretKey);
    try {
      final writeResult = await writer.writeIfAbsent(result.payload);
      switch (writeResult.outcome) {
        case SnapshotWriteOutcome.alreadyExists:
          output(
            'Snapshot already exists with identical data. No write required.',
          );
        case SnapshotWriteOutcome.inserted:
          output('Snapshot inserted and verified by read-back.');
        case SnapshotWriteOutcome.updated:
          output('Snapshot safely improved and verified by read-back.');
      }
      return 0;
    } on SnapshotWriteException catch (exception) {
      final message = exception.message.startsWith('station_id=')
          ? exception.message
          : 'station_id=${result.stationId}; ${exception.message}';
      error(message);
      return 1;
    } on Object {
      error('Snapshot write failed.');
      return 1;
    } finally {
      writer.close();
    }
  }

  Future<int> _runDryRun(List<String> stationIds) async {
    if (stationIds.length != 1 || !stations.containsKey(stationIds.single)) {
      error('Unknown or missing station id. Use --station-id=bazias.');
      return 64;
    }
    final result = await collect(
      stationIds.single,
      stations[stationIds.single]!,
    );
    _printResult(result, output);
    _printSummary(SnapshotRunSummary([result]), output);
    return 0;
  }

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
            argument.startsWith('--station-id=') ||
            argument.startsWith('--confirm-station-id='),
      );

  static bool _isValidSupabaseUrl(String value) =>
      RegExp(r'^https://[A-Za-z0-9-]+\.supabase\.co$').hasMatch(value);
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

void _printResult(StationSnapshotResult result, void Function(String) output) {
  final data = result.payload;
  output('station id: ${result.stationId}');
  output('station name: ${result.stationName}');
  output('observation date: ${data.observationDate}');
  output('level_cm: ${data.levelCm}');
  output('level_source: ${data.levelSource}');
  output(
    'level_measured_at: ${data.levelMeasuredAt?.toUtc().toIso8601String()}',
  );
  output('daily_delta_cm: ${data.dailyDeltaCm}');
  output('delta_method: ${data.deltaMethod}');
  output('delta_source: ${data.deltaSource}');
  output(
    'delta_measured_at: ${data.deltaMeasuredAt?.toUtc().toIso8601String()}',
  );
  output(
    'delta_base_measured_at: ${data.deltaBaseMeasuredAt?.toUtc().toIso8601String()}',
  );
  output('quality: ${data.quality}');
  for (final failure in result.failures) {
    output(
      'provider error ${failure.source.databaseValue}: ${failure.message}',
    );
  }
}

void _printSummary(SnapshotRunSummary summary, void Function(String) output) {
  output(
    'summary: total stations=${summary.totalStations}; '
    'valid=${summary.valid}; partial=${summary.partial}; stale=${summary.stale}; '
    'provider_error=${summary.providerError}; unknown=${summary.unknown}; '
    'without delta=${summary.withoutDelta}; unexpected errors=0',
  );
}
