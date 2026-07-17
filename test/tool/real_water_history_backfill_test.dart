import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart';

import '../../tool/daily_water_snapshot_collector.dart' as collector;
import '../../tool/real_water_history_backfill.dart';
import '../../tool/src/daily_water_snapshot_collector.dart';
import '../../tool/src/daily_water_snapshot_supabase_writer.dart';
import '../../tool/src/real_water_history_backfill.dart';

void main() {
  setUpAll(initializeTimeZones);

  ProviderReading reading({
    required int level,
    required String timestamp,
    SnapshotSource source = SnapshotSource.danubeHis,
  }) => ProviderReading(
    source: source,
    levelCm: level,
    measuredAt: DateTime.parse(timestamp),
  );

  DailyWaterSnapshotPayload payload({
    required int level,
    required String timestamp,
    required SnapshotSource source,
  }) => DailyWaterSnapshotPayload(
    stationId: 'station-a',
    observationDate: DailyWaterSnapshotBuilder.observationDateFor(
      DateTime.parse(timestamp),
    ),
    levelCm: level,
    levelSource: source.databaseValue,
    levelMeasuredAt: DateTime.parse(timestamp),
    dailyDeltaCm: null,
    deltaSource: null,
    deltaMeasuredAt: null,
    deltaBaseMeasuredAt: null,
    deltaMethod: SnapshotDeltaMethod.unavailable.databaseValue,
    quality: SnapshotQuality.partial.databaseValue,
  );

  test('backfill keeps one newest real observation per Bucharest day', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 7,
      readings: [
        reading(level: 490, timestamp: '2026-07-01T03:00:00Z'),
        reading(level: 500, timestamp: '2026-07-11T03:00:00Z'),
        reading(level: 501, timestamp: '2026-07-11T08:00:00Z'),
        reading(level: 503, timestamp: '2026-07-13T03:00:00Z'),
        reading(
          level: 509,
          timestamp: '2026-07-17T09:00:00Z',
          source: SnapshotSource.danubeFis,
        ),
      ],
    );

    expect(payloads.map((payload) => payload.observationDate), [
      '2026-07-11',
      '2026-07-13',
      '2026-07-17',
    ]);
    expect(payloads.map((payload) => payload.levelCm), [501, 503, 509]);
    expect(payloads.map((payload) => payload.levelSource), [
      'DanubeHIS',
      'DanubeHIS',
      'DanubeFIS',
    ]);
    expect(payloads[1].dailyDeltaCm, 2);
    expect(payloads[2].dailyDeltaCm, isNull);
    expect(
      payloads.map((payload) => payload.observationDate).toSet().length,
      payloads.length,
    );
  });

  test('missing days stay missing and current level is never copied back', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 30,
      readings: [
        reading(
          level: 537,
          timestamp: '2026-07-17T09:00:00Z',
          source: SnapshotSource.danubeFis,
        ),
      ],
    );

    expect(payloads, hasLength(1));
    expect(payloads.single.observationDate, '2026-07-17');
    expect(payloads.single.levelCm, 537);
    expect(payloads.single.dailyDeltaCm, isNull);
  });

  test('same real input produces the same idempotent payload plan', () {
    final input = [
      reading(level: 10, timestamp: '2026-07-15T03:00:00Z'),
      reading(level: 12, timestamp: '2026-07-16T03:00:00Z'),
    ];
    const builder = RealWaterHistoryBackfillBuilder();
    final first = builder.build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 7,
      readings: input,
    );
    final second = builder.build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 7,
      readings: input.reversed,
    );

    expect(
      second.map((payload) => payload.toJson()),
      first.map((payload) => payload.toJson()),
    );
  });

  test(
    'rerunning an applied backfill inserts no duplicate station dates',
    () async {
      final writer = _MemoryWriter();
      final output = <String>[];
      final command = RealWaterHistoryBackfillCommand(
        stations: const {'station-a': 'Station A'},
        load: (_, _) async => RealHistoryLoadResult(
          readingsByStationId: {
            'station-a': [
              reading(level: 10, timestamp: '2026-07-15T03:00:00Z'),
              reading(level: 12, timestamp: '2026-07-16T03:00:00Z'),
            ],
          },
        ),
        writerFactory: (_, _) => writer,
        environment: const {
          'SUPABASE_URL': 'https://example.supabase.co',
          'SUPABASE_SECRET_KEY': 'test-secret-not-logged',
        },
        output: output.add,
        error: output.add,
        nowUtc: () => DateTime.parse('2026-07-17T12:00:00Z'),
      );
      final arguments = [
        '--station-id=station-a',
        '--days=7',
        '--apply',
        '--confirm-station-id=station-a',
      ];

      expect(await command.run(arguments), 0);
      final firstRows = writer.rows.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      expect(await command.run(arguments), 0);

      expect(writer.rows, hasLength(2));
      expect(
        writer.rows.map((key, value) => MapEntry(key, value.toJson())),
        firstRows,
      );
      expect(
        output.any((line) => line.contains('duplicate_or_unchanged=2')),
        isTrue,
      );
      expect(output.every((line) => !line.contains('test-secret')), isTrue);
    },
  );

  test(
    'one Supabase client survives multiple stations and an intermediate error',
    () async {
      final client = _LifecycleHttpClient(
        failInsertKey: 'station-a/2026-07-16',
      );
      var writerFactoryCalls = 0;
      final output = <String>[];
      final command = RealWaterHistoryBackfillCommand(
        stations: const {'station-a': 'Station A', 'station-b': 'Station B'},
        load: (stations, _) async => RealHistoryLoadResult(
          readingsByStationId: {
            for (final id in stations.keys)
              id: [
                reading(level: 10, timestamp: '2026-07-15T03:00:00Z'),
                reading(level: 12, timestamp: '2026-07-16T03:00:00Z'),
              ],
          },
        ),
        writerFactory: (url, key) {
          writerFactoryCalls++;
          return SupabaseDailyWaterSnapshotWriter(
            supabaseUrl: url,
            secretKey: key,
            client: client,
            nowUtc: () => DateTime.parse('2026-07-17T12:00:00Z'),
          );
        },
        environment: const {
          'SUPABASE_URL': 'https://example.supabase.co',
          'SUPABASE_SECRET_KEY': 'lifecycle-test-secret',
        },
        output: output.add,
        error: output.add,
        nowUtc: () => DateTime.parse('2026-07-17T12:00:00Z'),
      );

      final result = await command.run([
        '--all-stations',
        '--days=3',
        '--apply',
        '--confirm-station-id=station-a',
        '--confirm-station-id=station-b',
      ]);

      expect(result, 1);
      expect(writerFactoryCalls, 1);
      expect(client.requestCount, 15);
      expect(client.insertedKeys, {
        'station-a/2026-07-15',
        'station-b/2026-07-15',
        'station-b/2026-07-16',
      });
      expect(client.closeCount, 1);
      expect(client.operationsAfterClose, 0);
      expect(client.events.last, 'close');
      expect(
        output.any((line) => line.contains('synthetic intermediate failure')),
        isTrue,
      );
      expect(
        output.every((line) => !line.contains('lifecycle-test-secret')),
        isTrue,
      );
    },
  );

  test('newer DanubeFIS cannot replace AFDJ for the same local day', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 1,
      readings: [
        reading(
          level: 540,
          timestamp: '2026-07-17T10:00:00Z',
          source: SnapshotSource.danubeFis,
        ),
        reading(
          level: 535,
          timestamp: '2026-07-17T08:00:00Z',
          source: SnapshotSource.afdj,
        ),
      ],
    );

    expect(payloads.single.levelCm, 535);
    expect(payloads.single.levelSource, 'AFDJ');

    final merge = const DailyWaterSnapshotMerger().merge(
      existing: payload(
        level: 535,
        timestamp: '2026-07-17T08:00:00Z',
        source: SnapshotSource.afdj,
      ),
      incoming: payload(
        level: 540,
        timestamp: '2026-07-17T10:00:00Z',
        source: SnapshotSource.danubeFis,
      ),
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
    );
    expect(merge.outcome, DailyWaterSnapshotMergeOutcome.identicalNoOp);
    expect(merge.payload.levelSource, 'AFDJ');
    expect(merge.payload.levelCm, 535);
  });

  test('higher-authority source replaces a lower-authority snapshot', () {
    final merge = const DailyWaterSnapshotMerger().merge(
      existing: payload(
        level: 540,
        timestamp: '2026-07-17T10:00:00Z',
        source: SnapshotSource.danubeFis,
      ),
      incoming: payload(
        level: 535,
        timestamp: '2026-07-17T08:00:00Z',
        source: SnapshotSource.afdj,
      ),
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
    );

    expect(merge.outcome, DailyWaterSnapshotMergeOutcome.improvedUpdate);
    expect(merge.payload.levelSource, 'AFDJ');
    expect(merge.payload.levelCm, 535);
  });

  test('newer timestamp wins between observations of equal authority', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 1,
      readings: [
        reading(
          level: 530,
          timestamp: '2026-07-17T08:00:00Z',
          source: SnapshotSource.danubeHis,
        ),
        reading(
          level: 532,
          timestamp: '2026-07-17T10:00:00Z',
          source: SnapshotSource.danubeHis,
        ),
      ],
    );

    expect(payloads.single.levelCm, 532);
    expect(
      payloads.single.levelMeasuredAt,
      DateTime.parse('2026-07-17T10:00:00Z'),
    );

    final merge = const DailyWaterSnapshotMerger().merge(
      existing: payload(
        level: 530,
        timestamp: '2026-07-17T08:00:00Z',
        source: SnapshotSource.danubeHis,
      ),
      incoming: payload(
        level: 532,
        timestamp: '2026-07-17T10:00:00Z',
        source: SnapshotSource.danubeHis,
      ),
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
    );
    expect(merge.outcome, DailyWaterSnapshotMergeOutcome.improvedUpdate);
    expect(merge.payload.levelCm, 532);
  });

  test('equal authority and timestamp are deterministic and idempotent', () {
    final firstReading = reading(
      level: 534,
      timestamp: '2026-07-17T10:00:00Z',
      source: SnapshotSource.danubeHis,
    );
    final duplicate = reading(
      level: 532,
      timestamp: '2026-07-17T10:00:00Z',
      source: SnapshotSource.danubeHis,
    );
    const builder = RealWaterHistoryBackfillBuilder();
    final first = builder.build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 1,
      readings: [firstReading, duplicate],
    );
    final reversed = builder.build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 1,
      readings: [duplicate, firstReading],
    );

    expect(first, hasLength(1));
    expect(reversed.single.toJson(), first.single.toJson());
    expect(first.single.levelCm, 532);
  });

  test('day window uses Bucharest calendar dates across spring DST', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-04-26T21:30:00Z'),
      days: 30,
      readings: [
        reading(level: 500, timestamp: '2026-03-28T10:00:00Z'),
        reading(level: 501, timestamp: '2026-03-29T10:00:00Z'),
      ],
    );

    expect(payloads.map((value) => value.observationDate), ['2026-03-29']);
  });

  test('observations around UTC midnight use the Bucharest local date', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 2,
      readings: [
        reading(level: 500, timestamp: '2026-07-16T20:30:00Z'),
        reading(level: 501, timestamp: '2026-07-16T21:30:00Z'),
      ],
    );

    expect(payloads.map((value) => value.observationDate), [
      '2026-07-16',
      '2026-07-17',
    ]);
  });

  test('negative real levels are preserved exactly', () {
    final payloads = const RealWaterHistoryBackfillBuilder().build(
      stationId: 'station-a',
      nowUtc: DateTime.parse('2026-07-17T12:00:00Z'),
      days: 1,
      readings: [reading(level: -27, timestamp: '2026-07-17T09:00:00Z')],
    );

    expect(payloads.single.levelCm, -27);
  });

  test('canonical roster has exactly 23 stations and excludes Periprava', () {
    expect(collector.canonicalWaterStations.keys, [
      'bazias',
      'moldova_veche',
      'drencova',
      'orsova',
      'drobeta_turnu_severin',
      'gruia',
      'cetate',
      'calafat',
      'rast',
      'bechet',
      'corabia',
      'turnu_magurele',
      'zimnicea',
      'giurgiu',
      'oltenita',
      'calarasi',
      'cernavoda',
      'harsova',
      'braila',
      'galati',
      'isaccea',
      'tulcea',
      'sulina',
    ]);
    expect(
      collector.canonicalWaterStations.keys.any(
        (id) => id.toLowerCase().contains('periprava'),
      ),
      isFalse,
    );
    expect(
      collector.canonicalWaterStations.values.any(
        (name) => name.toLowerCase().contains('periprava'),
      ),
      isFalse,
    );
  });

  test(
    'default run does not write and incomplete confirmations are refused',
    () async {
      final writer = _MemoryWriter();
      var writerFactoryCalls = 0;
      var loadCalls = 0;
      final command = RealWaterHistoryBackfillCommand(
        stations: const {'station-a': 'Station A', 'station-b': 'Station B'},
        load: (stations, _) async {
          loadCalls++;
          return RealHistoryLoadResult(
            readingsByStationId: {
              for (final id in stations.keys)
                id: [reading(level: 10, timestamp: '2026-07-17T03:00:00Z')],
            },
          );
        },
        writerFactory: (_, _) {
          writerFactoryCalls++;
          return writer;
        },
        environment: const {
          'SUPABASE_URL': 'https://example.supabase.co',
          'SUPABASE_SECRET_KEY': 'test-secret',
        },
        output: (_) {},
        error: (_) {},
        nowUtc: () => DateTime.parse('2026-07-17T12:00:00Z'),
      );

      expect(await command.run(['--all-stations', '--days=1']), 0);
      expect(writerFactoryCalls, 0);
      expect(writer.rows, isEmpty);
      expect(loadCalls, 1);

      expect(
        await command.run([
          '--all-stations',
          '--days=1',
          '--apply',
          '--confirm-station-id=station-a',
        ]),
        64,
      );
      expect(writerFactoryCalls, 0);
      expect(loadCalls, 1);
    },
  );

  test(
    'unexpected exceptions redact environment secrets and credential URLs',
    () async {
      const secret = 'unexpected-supabase-secret';
      const token = 'unexpected-provider-token';
      const credentialUrl = 'https://user:password@example.test/history';
      final output = <String>[];
      final command = RealWaterHistoryBackfillCommand(
        stations: const {'station-a': 'Station A'},
        load: (_, _) async => throw StateError(
          'failure secret=$secret token=$token endpoint=$credentialUrl',
        ),
        writerFactory: (_, _) => _MemoryWriter(),
        environment: const {
          'SUPABASE_SECRET_KEY': secret,
          'PROVIDER_API_TOKEN': token,
          'PROVIDER_URL': credentialUrl,
        },
        output: output.add,
        error: output.add,
        nowUtc: () => DateTime.parse('2026-07-17T12:00:00Z'),
      );

      expect(
        await command.run(['--station-id=station-a', '--days=1', '--dry-run']),
        1,
      );
      expect(output.join(' '), isNot(contains(secret)));
      expect(output.join(' '), isNot(contains(token)));
      expect(output.join(' '), isNot(contains(credentialUrl)));
      expect(output.join(' '), contains('[redacted]'));
    },
  );
}

class _MemoryWriter implements DailyWaterSnapshotWriter {
  final rows = <String, DailyWaterSnapshotPayload>{};

  @override
  Future<SnapshotWriteResult> writeIfAbsent(
    DailyWaterSnapshotPayload payload,
  ) async {
    final key = '${payload.stationId}/${payload.observationDate}';
    if (rows.containsKey(key)) return const SnapshotWriteResult.alreadyExists();
    rows[key] = payload;
    return const SnapshotWriteResult.inserted();
  }

  @override
  void close() {}
}

class _LifecycleHttpClient extends http.BaseClient {
  _LifecycleHttpClient({required this.failInsertKey});

  final String failInsertKey;
  final Map<String, Map<String, Object?>> _rows = {};
  final Set<String> insertedKeys = {};
  final List<String> events = [];
  int requestCount = 0;
  int closeCount = 0;
  int operationsAfterClose = 0;
  bool _closed = false;
  bool _failedConfiguredInsert = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      operationsAfterClose++;
      throw http.ClientException('operation attempted after close');
    }
    requestCount++;
    events.add('${request.method} ${request.url.path}');

    if (request.method == 'GET' && request.url.path.endsWith('/stations')) {
      final stationId = _filterValue(request.url, 'id');
      return _jsonResponse(200, [
        {'id': stationId},
      ]);
    }

    if (request.method == 'GET' &&
        request.url.path.endsWith('/daily_water_snapshots')) {
      final key = _snapshotKey(request.url);
      final row = _rows[key];
      return _jsonResponse(200, row == null ? [] : [row]);
    }

    if (request.method == 'POST' &&
        request.url.path.endsWith('/daily_water_snapshots')) {
      final body = request is http.Request
          ? request.body
          : await request.finalize().bytesToString();
      final row = Map<String, Object?>.from(jsonDecode(body) as Map);
      final key = '${row['station_id']}/${row['observation_date']}';
      if (!_failedConfiguredInsert && key == failInsertKey) {
        _failedConfiguredInsert = true;
        return _jsonResponse(500, {
          'message': 'synthetic intermediate failure',
        });
      }
      final stored = <String, Object?>{
        ...row,
        'updated_at': '2026-07-17T12:00:00.000Z',
      };
      _rows[key] = stored;
      insertedKeys.add(key);
      return _jsonResponse(201, [stored]);
    }

    return _jsonResponse(405, {'message': 'unexpected synthetic request'});
  }

  String _snapshotKey(Uri uri) =>
      '${_filterValue(uri, 'station_id')}/${_filterValue(uri, 'observation_date')}';

  static String _filterValue(Uri uri, String name) =>
      uri.queryParameters[name]!.replaceFirst('eq.', '');

  static http.StreamedResponse _jsonResponse(int statusCode, Object body) =>
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
        statusCode,
        headers: const {'content-type': 'application/json'},
      );

  @override
  void close() {
    closeCount++;
    _closed = true;
    events.add('close');
    super.close();
  }
}
