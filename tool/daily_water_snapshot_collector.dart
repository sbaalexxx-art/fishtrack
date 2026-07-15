import 'dart:io';

import 'package:timezone/data/latest.dart';

import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/afdj_water_provider.dart';
import 'package:fishtrack/repositories/danube_fis_water_provider.dart';
import 'package:fishtrack/repositories/danube_his_water_provider.dart';
import 'src/daily_water_snapshot_collector.dart';

const _stations = <String, String>{'bazias': 'Baziaș'};

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/daily_water_snapshot_collector.dart '
      '--station-id=<id> [--dry-run]',
    );
    return;
  }
  if (arguments.contains('--apply')) {
    stderr.writeln('Apply mode is not enabled in RC12.2B-3A.');
    exitCode = 64;
    return;
  }
  final stationId = arguments
      .where((argument) => argument.startsWith('--station-id='))
      .map((argument) => argument.substring('--station-id='.length))
      .cast<String?>()
      .firstOrNull;
  if (stationId == null || !_stations.containsKey(stationId)) {
    stderr.writeln('Unknown or missing station id. Use --station-id=bazias.');
    exitCode = 64;
    return;
  }
  initializeTimeZones();
  final result = await _collect(stationId, _stations[stationId]!);
  _printResult(result);
  _printSummary(SnapshotRunSummary([result]));
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

void _printResult(StationSnapshotResult result) {
  final data = result.payload;
  stdout.writeln('station id: ${result.stationId}');
  stdout.writeln('station name: ${result.stationName}');
  stdout.writeln('observation date: ${data.observationDate}');
  stdout.writeln('level_cm: ${data.levelCm}');
  stdout.writeln('level_source: ${data.levelSource}');
  stdout.writeln(
    'level_measured_at: ${data.levelMeasuredAt?.toUtc().toIso8601String()}',
  );
  stdout.writeln('daily_delta_cm: ${data.dailyDeltaCm}');
  stdout.writeln('delta_method: ${data.deltaMethod}');
  stdout.writeln('delta_source: ${data.deltaSource}');
  stdout.writeln(
    'delta_measured_at: ${data.deltaMeasuredAt?.toUtc().toIso8601String()}',
  );
  stdout.writeln(
    'delta_base_measured_at: ${data.deltaBaseMeasuredAt?.toUtc().toIso8601String()}',
  );
  stdout.writeln('quality: ${data.quality}');
  for (final failure in result.failures) {
    stdout.writeln(
      'provider error ${failure.source.databaseValue}: ${failure.message}',
    );
  }
}

void _printSummary(SnapshotRunSummary summary) {
  stdout.writeln(
    'summary: total stations=${summary.totalStations}; '
    'valid=${summary.valid}; partial=${summary.partial}; stale=${summary.stale}; '
    'provider_error=${summary.providerError}; unknown=${summary.unknown}; '
    'without delta=${summary.withoutDelta}; unexpected errors=0',
  );
}
