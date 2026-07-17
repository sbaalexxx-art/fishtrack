import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart';

import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/repositories/afdj_water_provider.dart';
import 'package:fishtrack/repositories/danube_fis_water_provider.dart';
import 'package:fishtrack/repositories/danube_his_water_provider.dart';

import 'daily_water_snapshot_collector.dart'
    show canonicalRemoteStationIds, canonicalWaterStations;
import 'src/daily_water_snapshot_collector.dart';
import 'src/daily_water_snapshot_supabase_writer.dart';
import 'src/real_water_history_backfill.dart';

typedef RealHistoryLoader =
    Future<RealHistoryLoadResult> Function(
      Map<String, String> stations,
      int days,
    );
typedef HistoryWriterFactory =
    DailyWaterSnapshotWriter Function(String supabaseUrl, String secretKey);

class RealHistoryLoadResult {
  const RealHistoryLoadResult({
    required this.readingsByStationId,
    this.unavailableSources = const <String>[],
  });

  final Map<String, List<ProviderReading>> readingsByStationId;
  final List<String> unavailableSources;
}

Future<void> main(List<String> arguments) async {
  initializeTimeZones();
  final command = RealWaterHistoryBackfillCommand(
    stations: canonicalWaterStations,
    remoteStationIds: canonicalRemoteStationIds,
    load: _loadOfficialHistory,
    writerFactory: (url, key) => SupabaseDailyWaterSnapshotWriter(
      supabaseUrl: url,
      secretKey: key,
      client: http.Client(),
    ),
    environment: Platform.environment,
    output: stdout.writeln,
    error: stderr.writeln,
    nowUtc: () => DateTime.now().toUtc(),
  );
  exitCode = await command.run(arguments);
}

class RealWaterHistoryBackfillCommand {
  RealWaterHistoryBackfillCommand({
    required this.stations,
    this.remoteStationIds = const <String, String>{},
    required this.load,
    required this.writerFactory,
    required this.environment,
    required this.output,
    required this.error,
    required this.nowUtc,
  });

  final Map<String, String> stations;
  final Map<String, String> remoteStationIds;
  final RealHistoryLoader load;
  final HistoryWriterFactory writerFactory;
  final Map<String, String> environment;
  final void Function(String message) output;
  final void Function(String message) error;
  final DateTime Function() nowUtc;

  Future<int> run(List<String> arguments) async {
    if (arguments.contains('--help')) {
      output(
        'Usage: dart run tool/real_water_history_backfill.dart '
        '--all-stations --days=30 --dry-run; apply additionally requires '
        '--apply and one matching --confirm-station-id per station.',
      );
      return 0;
    }
    if (!_hasOnlySupportedArguments(arguments)) {
      error('Unsupported argument. Secrets are accepted only via environment.');
      return 64;
    }

    final days = _days(arguments);
    if (days == null) {
      error('--days must be an integer between 1 and 30.');
      return 64;
    }
    final selectedIds = _selectStationIds(arguments);
    if (selectedIds == null) {
      error('Select known --station-id values or --all-stations.');
      return 64;
    }

    final apply = arguments.contains('--apply');
    DailyWaterSnapshotWriter? writer;
    if (apply) {
      final confirmations = _argumentValues(arguments, '--confirm-station-id=');
      if (!_hasExactConfirmations(selectedIds, confirmations)) {
        error('Apply requires one exact confirmation for every station.');
        return 64;
      }
      final url = environment['SUPABASE_URL'];
      final key = environment['SUPABASE_SECRET_KEY'];
      if (url == null || !_isValidSupabaseUrl(url)) {
        error('Apply requires a valid SUPABASE_URL environment value.');
        return 64;
      }
      if (key == null || key.trim().isEmpty) {
        error('Apply requires SUPABASE_SECRET_KEY in the environment.');
        return 64;
      }
      writer = writerFactory(url, key);
    }

    try {
      final selected = <String, String>{
        for (final id in selectedIds) id: stations[id]!,
      };
      final loaded = await load(selected, days);
      for (final source in loaded.unavailableSources) {
        output('provider unavailable: $source');
      }
      return await _writePlans(
        selectedIds,
        loaded.readingsByStationId,
        days,
        writer,
      );
    } on Object catch (exception) {
      error(_safeError(exception, environment));
      return 1;
    } finally {
      writer?.close();
    }
  }

  Future<int> _writePlans(
    List<String> selectedIds,
    Map<String, List<ProviderReading>> readingsByStationId,
    int days,
    DailyWaterSnapshotWriter? writer,
  ) async {
    var insertedTotal = 0;
    var updatedTotal = 0;
    var unchangedTotal = 0;
    var failedTotal = 0;
    final now = nowUtc().toUtc();
    const builder = RealWaterHistoryBackfillBuilder();

    for (final canonicalId in selectedIds) {
      final remoteId = remoteStationIds[canonicalId] ?? canonicalId;
      final readings = readingsByStationId[canonicalId] ?? const [];
      final payloads = builder.build(
        stationId: remoteId,
        nowUtc: now,
        days: days,
        readings: readings,
      );
      var inserted = 0;
      var updated = 0;
      var unchanged = 0;
      var failed = 0;

      for (final payload in payloads) {
        if (writer == null) continue;
        try {
          final result = await writer.writeIfAbsent(payload);
          switch (result.outcome) {
            case SnapshotWriteOutcome.inserted:
              inserted++;
            case SnapshotWriteOutcome.updated:
              updated++;
            case SnapshotWriteOutcome.alreadyExists:
              unchanged++;
          }
        } on Object catch (exception) {
          failed++;
          error(
            'station_id=$canonicalId; date=${payload.observationDate}; '
            '${_safeError(exception, environment)}',
          );
        }
      }

      insertedTotal += inserted;
      updatedTotal += updated;
      unchangedTotal += unchanged;
      failedTotal += failed;
      final sources =
          payloads
              .map((payload) => payload.levelSource)
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
      final first = payloads.isEmpty ? null : payloads.first;
      final last = payloads.isEmpty ? null : payloads.last;
      final delta = payloads.length < 2 || first == null || last == null
          ? null
          : last.levelCm! - first.levelCm!;
      output(
        'station_id=$canonicalId; remote_station_id=$remoteId; '
        'found=${payloads.length}; inserted=$inserted; updated=$updated; '
        'duplicate_or_unchanged=$unchanged; failed=$failed; '
        'real_days=${payloads.length}; first=${_point(first)}; '
        'last=${_point(last)}; period_delta_cm=${delta ?? 'unavailable'}; '
        'sources=${sources.isEmpty ? 'none' : sources.join(',')}; '
        'status=${payloads.length < 2 ? 'REAL HISTORY INSUFFICIENT' : 'REAL HISTORY AVAILABLE'}',
      );
    }

    output(
      'backfill summary: stations=${selectedIds.length}; days=$days; '
      'inserted=$insertedTotal; updated=$updatedTotal; '
      'duplicate_or_unchanged=$unchangedTotal; failed=$failedTotal',
    );
    return failedTotal == 0 ? 0 : 1;
  }

  List<String>? _selectStationIds(List<String> arguments) {
    final all = arguments.contains('--all-stations');
    final ids = _argumentValues(arguments, '--station-id=');
    if (all) return ids.isEmpty ? stations.keys.toList(growable: false) : null;
    if (ids.isEmpty ||
        ids.toSet().length != ids.length ||
        ids.any((id) => !stations.containsKey(id))) {
      return null;
    }
    return ids;
  }

  static int? _days(List<String> arguments) {
    final values = _argumentValues(arguments, '--days=');
    if (values.length > 1) return null;
    final value = values.isEmpty ? 30 : int.tryParse(values.single);
    return value != null && value >= 1 && value <= 30 ? value : null;
  }

  static List<String> _argumentValues(List<String> arguments, String prefix) =>
      arguments
          .where((argument) => argument.startsWith(prefix))
          .map((argument) => argument.substring(prefix.length))
          .toList(growable: false);

  static bool _hasOnlySupportedArguments(List<String> arguments) =>
      arguments.every(
        (argument) =>
            argument == '--help' ||
            argument == '--apply' ||
            argument == '--dry-run' ||
            argument == '--all-stations' ||
            argument.startsWith('--days=') ||
            argument.startsWith('--station-id=') ||
            argument.startsWith('--confirm-station-id='),
      );

  static bool _hasExactConfirmations(
    List<String> selected,
    List<String> confirmations,
  ) =>
      selected.length == confirmations.length &&
      selected.toSet().containsAll(confirmations) &&
      confirmations.toSet().containsAll(selected);

  static bool _isValidSupabaseUrl(String value) =>
      RegExp(r'^https://[A-Za-z0-9-]+\.supabase\.co$').hasMatch(value);

  static String _point(DailyWaterSnapshotPayload? payload) => payload == null
      ? 'none'
      : '${payload.observationDate}@${payload.levelMeasuredAt!.toUtc().toIso8601String()}/${payload.levelCm}cm/${payload.levelSource}';
}

Future<RealHistoryLoadResult> _loadOfficialHistory(
  Map<String, String> stations,
  int days,
) async {
  const afdj = AfdjWaterProvider();
  const fis = DanubeFisWaterProvider();
  const his = DanubeHisWaterProvider();
  final names = stations.values.toList(growable: false);
  final unavailable = <String>[];
  Map<String, List<WaterLevel>> afdjLevels = const {};
  Map<String, List<WaterLevel>> fisLevels = const {};
  Map<String, List<WaterLevel>> hisLevels = const {};

  try {
    afdjLevels = await afdj.getLevels(names);
  } on Object {
    unavailable.add('AFDJ');
  }
  try {
    fisLevels = await fis.getLevels(names);
  } on Object {
    unavailable.add('DanubeFIS');
  }
  try {
    hisLevels = await his.getLevels(names, limit: days + 2, historyDays: days);
  } on Object {
    unavailable.add('DanubeHIS');
  }

  final readings = <String, List<ProviderReading>>{};
  for (final entry in stations.entries) {
    final normalized = DanubeHisWaterProvider.normalizedName(entry.value);
    final levels = <WaterLevel>[
      ...?afdjLevels[normalized],
      ...?fisLevels[normalized],
      ...?hisLevels[normalized],
    ];
    readings[entry.key] = levels
        .map(_providerReading)
        .whereType<ProviderReading>()
        .toList(growable: false);
  }
  return RealHistoryLoadResult(
    readingsByStationId: readings,
    unavailableSources: List<String>.unmodifiable(unavailable),
  );
}

ProviderReading? _providerReading(WaterLevel reading) {
  if (!reading.value.isFinite || reading.value != reading.value.round()) {
    return null;
  }
  final source = switch (reading.source) {
    WaterLevelSource.afdj => SnapshotSource.afdj,
    WaterLevelSource.danubeHis => SnapshotSource.danubeHis,
    WaterLevelSource.danubeFis => SnapshotSource.danubeFis,
    WaterLevelSource.inhga => null,
    WaterLevelSource.manualFallback => null,
  };
  return source == null
      ? null
      : ProviderReading(
          source: source,
          levelCm: reading.value.round(),
          measuredAt: reading.timestamp.toUtc(),
        );
}

String _safeError(Object error, Map<String, String> environment) {
  var text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final entry in environment.entries) {
    final name = entry.key.toUpperCase();
    final value = entry.value.trim();
    final sensitiveName =
        name.contains('SECRET') ||
        name.contains('TOKEN') ||
        name.contains('PASSWORD') ||
        name.contains('CREDENTIAL') ||
        name == 'API_KEY' ||
        name.endsWith('_API_KEY') ||
        name.endsWith('_PRIVATE_KEY');
    final credentialUrl =
        name.endsWith('_URL') &&
        Uri.tryParse(value)?.userInfo.isNotEmpty == true;
    if (value.isNotEmpty && (sensitiveName || credentialUrl)) {
      text = text.replaceAll(value, '[redacted]');
    }
  }
  text = text
      .replaceAll(
        RegExp(r'https?://[^\s/@:]+:[^\s/@]+@[^\s]+', caseSensitive: false),
        '[redacted-url]',
      )
      .replaceAll(
        RegExp(r'authorization\s*[:=]\s*\S+(?:\s+\S+)?', caseSensitive: false),
        'Authorization: [redacted]',
      )
      .replaceAll(
        RegExp(r'apikey\s*[:=]\s*\S+', caseSensitive: false),
        'apikey: [redacted]',
      );
  return text.length <= 160 ? text : '${text.substring(0, 160)}…';
}
