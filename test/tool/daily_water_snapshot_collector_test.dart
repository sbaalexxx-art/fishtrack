import 'dart:collection';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart';

import '../../tool/daily_water_snapshot_collector.dart';
import '../../tool/src/daily_water_snapshot_collector.dart';
import '../../tool/src/daily_water_snapshot_supabase_writer.dart';

void main() {
  setUpAll(initializeTimeZones);
  const builder = DailyWaterSnapshotBuilder();
  final now = DateTime.utc(2026, 1, 15, 12);

  ProviderReading reading(SnapshotSource source, int value, DateTime time) =>
      ProviderReading(source: source, levelCm: value, measuredAt: time);

  test('provider-reported delta is preserved', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [reading(SnapshotSource.danubeHis, 500, now)],
      reportedDeltas: [
        ProviderReportedDelta(
          deltaCm: 4,
          source: SnapshotSource.afdj,
          measuredAt: now,
        ),
      ],
    );
    expect(payload.dailyDeltaCm, 4);
    expect(payload.deltaMethod, 'provider_reported');
    expect(payload.deltaBaseMeasuredAt, isNull);
  });

  test('provider-reported wins over computed delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.danubeHis,
          500,
          now.subtract(const Duration(days: 1)),
        ),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
      reportedDeltas: [
        ProviderReportedDelta(
          deltaCm: 2,
          source: SnapshotSource.afdj,
          measuredAt: now,
        ),
      ],
    );
    expect(payload.dailyDeltaCm, 2);
    expect(payload.deltaMethod, 'provider_reported');
  });

  test('same-source history computes a delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.danubeHis,
          500,
          now.subtract(const Duration(days: 1)),
        ),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
    );
    expect(payload.dailyDeltaCm, 10);
    expect(payload.deltaMethod, 'computed_same_source');
    expect(payload.deltaBaseMeasuredAt, now.subtract(const Duration(days: 1)));
  });

  test('different sources do not compute a delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.afdj,
          500,
          now.subtract(const Duration(days: 1)),
        ),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
    );
    expect(payload.deltaMethod, 'unavailable');
    expect(payload.dailyDeltaCm, isNull);
  });

  test('newer or equal base cannot produce delta', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(SnapshotSource.danubeHis, 500, now),
        reading(SnapshotSource.danubeHis, 510, now),
      ],
    );
    expect(payload.deltaMethod, 'unavailable');
  });

  test('unavailable delta has null pairing fields', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [reading(SnapshotSource.danubeFis, 500, now)],
    );
    expect(payload.toJson()['daily_delta_cm'], isNull);
    expect(payload.toJson()['delta_source'], isNull);
    expect(payload.toJson()['delta_measured_at'], isNull);
    expect(payload.toJson()['delta_base_measured_at'], isNull);
  });

  test('level and delta preserve separate timestamps', () {
    final base = now.subtract(const Duration(hours: 24));
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(SnapshotSource.danubeHis, 490, base),
        reading(SnapshotSource.danubeHis, 500, now),
      ],
    );
    expect(payload.levelMeasuredAt, now);
    expect(payload.deltaMeasuredAt, now);
    expect(payload.deltaBaseMeasuredAt, base);
  });

  test('valid level is not replaced by failure', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [reading(SnapshotSource.danubeFis, 500, now)],
      failures: const [ProviderFailure(SnapshotSource.afdj, 'offline')],
    );
    expect(payload.levelCm, 500);
    expect(payload.quality, 'partial');
  });

  test('provider failures without data produce provider_error', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      failures: const [ProviderFailure(SnapshotSource.afdj, 'offline')],
      readings: const [],
    );
    expect(payload.quality, 'provider_error');
  });

  test('quality values are limited to SQL contract', () {
    expect(
      SnapshotQuality.values.map((value) => value.databaseValue),
      containsAll(<String>[
        'valid',
        'partial',
        'stale',
        'provider_error',
        'unknown',
      ]),
    );
  });

  test('payload uses quality and never quality_status', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: const [],
    );
    expect(payload.toJson().containsKey('quality'), isTrue);
    expect(payload.toJson().containsKey('quality_status'), isFalse);
  });

  test('winter Bucharest date differs at UTC midnight boundary', () {
    expect(
      DailyWaterSnapshotBuilder.observationDateFor(
        DateTime.utc(2026, 1, 1, 22, 30),
      ),
      '2026-01-02',
    );
  });

  test('summer Bucharest date uses DST', () {
    expect(
      DailyWaterSnapshotBuilder.observationDateFor(
        DateTime.utc(2026, 7, 1, 21, 30),
      ),
      '2026-07-02',
    );
  });

  test('UTC midnight proximity keeps Bucharest calendar day', () {
    expect(
      DailyWaterSnapshotBuilder.observationDateFor(
        DateTime.utc(2026, 1, 1, 21, 30),
      ),
      '2026-01-01',
    );
  });

  test('same input is deterministic', () {
    final readings = [
      reading(
        SnapshotSource.danubeHis,
        500,
        now.subtract(const Duration(hours: 2)),
      ),
      reading(SnapshotSource.danubeHis, 505, now),
    ];
    expect(
      builder
          .build(stationId: 'bazias', nowUtc: now, readings: readings)
          .toJson(),
      builder
          .build(stationId: 'bazias', nowUtc: now, readings: readings)
          .toJson(),
    );
  });

  test('provider order does not change payload', () {
    final first = [
      reading(SnapshotSource.danubeFis, 500, now),
      reading(
        SnapshotSource.danubeHis,
        490,
        now.subtract(const Duration(hours: 2)),
      ),
      reading(SnapshotSource.danubeHis, 495, now),
    ];
    expect(
      builder.build(stationId: 'bazias', nowUtc: now, readings: first).toJson(),
      builder
          .build(stationId: 'bazias', nowUtc: now, readings: first.reversed)
          .toJson(),
    );
  });

  test('level pairing is all-null without readings', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: const [],
    );
    expect([
      payload.levelCm,
      payload.levelSource,
      payload.levelMeasuredAt,
    ], everyElement(isNull));
  });

  test('empty successful collection is classified unknown', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: const [],
    );
    expect(payload.quality, 'unknown');
  });

  test('stale data is classified stale', () {
    final payload = builder.build(
      stationId: 'bazias',
      nowUtc: now,
      readings: [
        reading(
          SnapshotSource.danubeFis,
          500,
          now.subtract(const Duration(hours: 37)),
        ),
      ],
    );
    expect(payload.quality, 'stale');
  });

  test('summary classifies results and missing deltas', () {
    final valid = StationSnapshotResult(
      stationId: 'a',
      stationName: 'A',
      failures: const [],
      payload: builder.build(
        stationId: 'a',
        nowUtc: now,
        readings: [
          reading(
            SnapshotSource.danubeHis,
            1,
            now.subtract(const Duration(hours: 1)),
          ),
          reading(SnapshotSource.danubeHis, 2, now),
        ],
      ),
    );
    final partial = StationSnapshotResult(
      stationId: 'b',
      stationName: 'B',
      failures: const [],
      payload: builder.build(
        stationId: 'b',
        nowUtc: now,
        readings: [reading(SnapshotSource.danubeFis, 1, now)],
      ),
    );
    final summary = SnapshotRunSummary([valid, partial]);
    expect(summary.valid, 1);
    expect(summary.partial, 1);
    expect(summary.withoutDelta, 1);
  });

  DailyWaterSnapshotPayload validPayload() => builder.build(
    stationId: 'bazias',
    nowUtc: now,
    readings: [
      reading(
        SnapshotSource.danubeHis,
        500,
        now.subtract(const Duration(hours: 2)),
      ),
      reading(SnapshotSource.danubeHis, 503, now),
    ],
  );

  StationSnapshotResult validResult() => StationSnapshotResult(
    stationId: 'bazias',
    stationName: 'Baziaș',
    payload: validPayload(),
    failures: const [],
  );

  SupabaseDailyWaterSnapshotWriter writer(_RecordingClient client) =>
      SupabaseDailyWaterSnapshotWriter(
        supabaseUrl: 'https://example.invalid',
        secretKey: 'secret-test-key',
        client: client,
      );

  DailyWaterSnapshotCommand command({
    required _FakeWriter fakeWriter,
    required List<String> output,
    required List<String> errors,
    Map<String, String> environment = const {},
    SnapshotWriterFactory? customWriterFactory,
    void Function()? onCollect,
  }) => DailyWaterSnapshotCommand(
    stations: const {'bazias': 'Baziaș'},
    collect: (stationId, stationName) async {
      onCollect?.call();
      return validResult();
    },
    writerFactory: customWriterFactory ?? (_, _) => fakeWriter,
    environment: environment,
    output: output.add,
    error: errors.add,
  );

  test('dry-run does not use the writer', () async {
    final writer = _FakeWriter();
    final output = <String>[];
    final commandResult = await command(
      fakeWriter: writer,
      output: output,
      errors: <String>[],
    ).run(['--dry-run', '--station-id=bazias']);
    expect(commandResult, 0);
    expect(writer.used, isFalse);
    expect(output, isNotEmpty);
  });

  test('apply without station-id is refused', () async {
    final errors = <String>[];
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: errors,
    ).run(['--apply']);
    expect(result, 64);
    expect(errors.single, contains('--station-id=bazias'));
  });

  test('apply without confirmation is refused', () async {
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: <String>[],
    ).run(['--apply', '--station-id=bazias']);
    expect(result, 64);
  });

  test('mismatched confirmation is refused', () async {
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: <String>[],
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=other']);
    expect(result, 64);
  });

  test('missing SUPABASE_URL is refused before collection', () async {
    var collected = false;
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: <String>[],
      environment: const {'SUPABASE_SECRET_KEY': 'test-key'},
      onCollect: () => collected = true,
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
    expect(result, 64);
    expect(collected, isFalse);
  });

  test('missing SUPABASE_SECRET_KEY is refused before collection', () async {
    var collected = false;
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: <String>[],
      environment: const {'SUPABASE_URL': 'https://test.supabase.co'},
      onCollect: () => collected = true,
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
    expect(result, 64);
    expect(collected, isFalse);
  });

  test('complete apply arguments reach environment validation', () async {
    var collected = false;
    final errors = <String>[];
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: errors,
      environment: const {'SUPABASE_URL': 'https://test.supabase.co'},
      onCollect: () => collected = true,
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
    expect(result, 64);
    expect(collected, isFalse);
    expect(errors, ['Apply requires SUPABASE_SECRET_KEY in the environment.']);
    expect(errors.single, isNot(contains('Unsupported argument')));
  });

  test('sanitized station HTTP error reaches CLI output', () async {
    final errors = <String>[];
    final result = await command(
      fakeWriter: _FakeWriter(
        failure: const SnapshotWriteException(
          'Station verification request failed (HTTP 401): Invalid API key.',
        ),
      ),
      output: <String>[],
      errors: errors,
      environment: const {
        'SUPABASE_URL': 'https://test.supabase.co',
        'SUPABASE_SECRET_KEY': 'secret-test-key',
      },
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
    expect(result, 1);
    expect(errors, [
      'station_id=bazias; '
          'Station verification request failed (HTTP 401): Invalid API key.',
    ]);
    expect(errors.single, isNot(contains('Snapshot write failed.')));
    expect(errors.single, isNot(contains('secret-test-key')));
    expect(errors.single, isNot(contains('https://')));
  });

  test('SUPABASE_URL with /rest/v1 is refused before collection', () async {
    var collected = false;
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: <String>[],
      environment: const {
        'SUPABASE_URL': 'https://test.supabase.co/rest/v1',
        'SUPABASE_SECRET_KEY': 'secret-test-key',
      },
      onCollect: () => collected = true,
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
    expect(result, 64);
    expect(collected, isFalse);
  });

  test('SUPABASE_URL with whitespace is rejected before collection', () async {
    var collected = false;
    final result = await command(
      fakeWriter: _FakeWriter(),
      output: <String>[],
      errors: <String>[],
      environment: const {
        'SUPABASE_URL': ' https://test.supabase.co ',
        'SUPABASE_SECRET_KEY': 'secret-test-key',
      },
      onCollect: () => collected = true,
    ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
    expect(result, 64);
    expect(collected, isFalse);
  });

  test(
    'ClientException reaches CLI with a sanitized transport diagnostic',
    () async {
      final errors = <String>[];
      final result = await command(
        fakeWriter: _FakeWriter(),
        output: <String>[],
        errors: errors,
        environment: const {
          'SUPABASE_URL': 'https://test.supabase.co',
          'SUPABASE_SECRET_KEY': 'secret-test-key',
        },
        customWriterFactory: (_, key) => SupabaseDailyWaterSnapshotWriter(
          supabaseUrl: 'https://test.supabase.co',
          secretKey: key,
          client: _ThrowingClient(
            http.ClientException(
              'station endpoint unavailable at '
              'https://test.supabase.co/rest/v1/stations?apikey=secret-test-key',
            ),
          ),
        ),
      ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
      expect(result, 1);
      expect(errors.single, contains('station_id=bazias'));
      expect(errors.single, contains('Station verification transport failure'));
      expect(errors.single, contains('ClientException'));
      expect(errors.single, isNot(contains('secret-test-key')));
      expect(errors.single, isNot(contains('https://')));
    },
  );

  test(
    'legacy service-role environment variable cannot enable apply',
    () async {
      var collected = false;
      final errors = <String>[];
      final result = await command(
        fakeWriter: _FakeWriter(),
        output: <String>[],
        errors: errors,
        environment: const {
          'SUPABASE_URL': 'https://test.supabase.co',
          'SUPABASE_SERVICE_ROLE_KEY': 'legacy-test-key',
        },
        onCollect: () => collected = true,
      ).run(['--apply', '--station-id=bazias', '--confirm-station-id=bazias']);
      expect(result, 64);
      expect(collected, isFalse);
      expect(errors.single, contains('SUPABASE_SECRET_KEY'));
    },
  );

  test('invalid payload makes no request', () async {
    final client = _RecordingClient();
    final invalid = DailyWaterSnapshotPayload(
      stationId: '',
      observationDate: '2026-01-15',
      levelCm: null,
      levelSource: null,
      levelMeasuredAt: null,
      dailyDeltaCm: null,
      deltaSource: null,
      deltaMeasuredAt: null,
      deltaBaseMeasuredAt: null,
      deltaMethod: 'unavailable',
      quality: 'unknown',
    );
    await expectLater(
      writer(client).writeIfAbsent(invalid),
      throwsA(isA<SnapshotWriteException>()),
    );
    expect(client.requests, isEmpty);
  });

  test('absent remote station makes no snapshot write', () async {
    final client = _RecordingClient.json([const []]);
    await expectLater(
      writer(client).writeIfAbsent(validPayload()),
      throwsA(isA<SnapshotWriteException>()),
    );
    expect(client.requests, hasLength(1));
    expect(client.requests.single.method, 'GET');
  });

  test('absent row produces exactly one insert', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [payload.toJson()],
    ]);
    final result = await writer(client).writeIfAbsent(payload);
    expect(result.outcome, SnapshotWriteOutcome.inserted);
    expect(
      client.requests.where((request) => request.method == 'POST'),
      hasLength(1),
    );
  });

  test('identical existing row is an idempotent no-op', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      [payload.toJson()],
    ]);
    final result = await writer(client).writeIfAbsent(payload);
    expect(result.outcome, SnapshotWriteOutcome.alreadyExists);
    expect(
      client.requests.where((request) => request.method == 'POST'),
      isEmpty,
    );
  });

  test('different existing row is refused without update', () async {
    final payload = validPayload();
    final different = {...payload.toJson(), 'quality': 'partial'};
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      [different],
    ]);
    await expectLater(
      writer(client).writeIfAbsent(payload),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('will not overwrite'),
        ),
      ),
    );
    expect(client.requests.every((request) => request.method == 'GET'), isTrue);
  });

  test('multiple existing rows are an integrity error', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      [payload.toJson(), payload.toJson()],
    ]);
    await expectLater(
      writer(client).writeIfAbsent(payload),
      throwsA(isA<SnapshotWriteException>()),
    );
    expect(client.requests, hasLength(2));
  });

  test('identical read-back produces success', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [payload.toJson()],
    ]);
    expect(
      (await writer(client).writeIfAbsent(payload)).outcome,
      SnapshotWriteOutcome.inserted,
    );
  });

  test('different read-back errors without delete or update', () async {
    final payload = validPayload();
    final different = {...payload.toJson(), 'daily_delta_cm': 99};
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [different],
    ]);
    await expectLater(
      writer(client).writeIfAbsent(payload),
      throwsA(isA<SnapshotWriteException>()),
    );
    expect(
      client.requests.map((request) => request.method),
      isNot(containsAll(<String>['PATCH', 'DELETE'])),
    );
  });

  test('writer errors never expose the secret key', () async {
    const key = 'secret-test-key';
    final client = _RecordingClient.json([const []], statusCode: 500);
    try {
      await writer(client).writeIfAbsent(validPayload());
      fail('Expected a writer error.');
    } on SnapshotWriteException catch (error) {
      expect(error.message, isNot(contains(key)));
    }
  });

  test(
    'station verification error includes a sanitized HTTP diagnostic',
    () async {
      final client = _RecordingClient.json([
        {
          'message':
              'Station unavailable at https://example.invalid/rest/v1/stations '
              'Authorization: Bearer secret-test-key',
        },
      ], statusCode: 503);
      try {
        await writer(client).writeIfAbsent(validPayload());
        fail('Expected a writer error.');
      } on SnapshotWriteException catch (error) {
        expect(
          error.message,
          contains('Station verification request failed (HTTP 503)'),
        );
        expect(error.message, contains('Station unavailable'));
        expect(error.message, isNot(contains('https://')));
        expect(error.message, isNot(contains('secret-test-key')));
        expect(error.message, isNot(contains('Bearer ')));
      }
    },
  );

  test('writer payload never sends quality_status', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [payload.toJson()],
    ]);
    await writer(client).writeIfAbsent(payload);
    final body =
        jsonDecode(
              (client.requests.firstWhere((request) => request.method == 'POST')
                      as http.Request)
                  .body,
            )
            as Map<String, dynamic>;
    expect(body.containsKey('quality_status'), isFalse);
  });

  test('writer payload never sends database-managed fields', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [payload.toJson()],
    ]);
    await writer(client).writeIfAbsent(payload);
    final body =
        jsonDecode(
              (client.requests.firstWhere((request) => request.method == 'POST')
                      as http.Request)
                  .body,
            )
            as Map<String, dynamic>;
    expect(
      body.keys,
      isNot(containsAll(<String>['id', 'created_at', 'updated_at'])),
    );
  });

  test('secret key is used only in the apikey request header', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [payload.toJson()],
    ]);
    await writer(client).writeIfAbsent(payload);
    final post =
        client.requests.firstWhere((request) => request.method == 'POST')
            as http.Request;
    expect(post.headers['apikey'], 'secret-test-key');
    expect(post.headers.containsKey('Authorization'), isFalse);
    expect(post.headers['Prefer'], 'return=representation');
    expect(post.url.toString(), isNot(contains('secret-test-key')));
    expect(post.body, isNot(contains('secret-test-key')));
  });

  test('writer has no automatic write retry', () async {
    final payload = validPayload();
    final client = _RecordingClient.json(
      [
        [
          const {'id': 'bazias'},
        ],
        const [],
        const [],
      ],
      statusCodes: [200, 200, 500],
    );
    await expectLater(
      writer(client).writeIfAbsent(payload),
      throwsA(isA<SnapshotWriteException>()),
    );
    expect(client.requests, hasLength(3));
    expect(
      client.requests.where((request) => request.method == 'POST'),
      hasLength(1),
    );
  });

  test('repeated operation becomes idempotent no-op', () async {
    final payload = validPayload();
    final client = _RecordingClient.json([
      [
        const {'id': 'bazias'},
      ],
      const [],
      [payload.toJson()],
      [payload.toJson()],
      [
        const {'id': 'bazias'},
      ],
      [payload.toJson()],
    ]);
    final snapshotWriter = writer(client);
    expect(
      (await snapshotWriter.writeIfAbsent(payload)).outcome,
      SnapshotWriteOutcome.inserted,
    );
    expect(
      (await snapshotWriter.writeIfAbsent(payload)).outcome,
      SnapshotWriteOutcome.alreadyExists,
    );
    expect(
      client.requests.where((request) => request.method == 'POST'),
      hasLength(1),
    );
  });
}

class _FakeWriter implements DailyWaterSnapshotWriter {
  _FakeWriter({this.failure});

  final SnapshotWriteException? failure;
  bool used = false;
  bool closed = false;

  @override
  Future<SnapshotWriteResult> writeIfAbsent(
    DailyWaterSnapshotPayload payload,
  ) async {
    used = true;
    if (failure != null) throw failure!;
    return const SnapshotWriteResult.inserted();
  }

  @override
  void close() => closed = true;
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient._(this._responses);

  factory _RecordingClient() =>
      _RecordingClient._(Queue<http.StreamedResponse>());

  factory _RecordingClient.json(
    List<Object> bodies, {
    int statusCode = 200,
    List<int>? statusCodes,
  }) => _RecordingClient._(
    Queue<http.StreamedResponse>.from(
      bodies.indexed.map(
        (entry) => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(jsonEncode(entry.$2))),
          statusCodes?[entry.$1] ?? statusCode,
        ),
      ),
    ),
  );

  final Queue<http.StreamedResponse> _responses;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) throw StateError('Unexpected request.');
    return _responses.removeFirst();
  }
}

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}
