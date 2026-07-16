import 'dart:convert';

import 'package:http/http.dart' as http;

import 'daily_water_snapshot_collector.dart';

const _contractFields = <String>[
  'station_id',
  'observation_date',
  'level_cm',
  'level_source',
  'level_measured_at',
  'daily_delta_cm',
  'delta_source',
  'delta_measured_at',
  'delta_base_measured_at',
  'delta_method',
  'quality',
];

enum SnapshotWriteOutcome { inserted, updated, alreadyExists }

class SnapshotWriteResult {
  const SnapshotWriteResult._(this.outcome, {this.differingFields = const []});

  const SnapshotWriteResult.inserted() : this._(SnapshotWriteOutcome.inserted);

  const SnapshotWriteResult.alreadyExists()
    : this._(SnapshotWriteOutcome.alreadyExists);

  const SnapshotWriteResult.updated() : this._(SnapshotWriteOutcome.updated);

  final SnapshotWriteOutcome outcome;
  final List<String> differingFields;
}

class SnapshotWriteException implements Exception {
  const SnapshotWriteException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class DailyWaterSnapshotWriter {
  Future<SnapshotWriteResult> writeIfAbsent(DailyWaterSnapshotPayload payload);

  void close();
}

class SupabaseDailyWaterSnapshotWriter implements DailyWaterSnapshotWriter {
  SupabaseDailyWaterSnapshotWriter({
    required String supabaseUrl,
    required String secretKey,
    required http.Client client,
    DateTime Function()? nowUtc,
  }) : _supabaseUrl = supabaseUrl,
       _secretKey = secretKey,
       _client = client,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final String _supabaseUrl;
  final String _secretKey;
  final http.Client _client;
  final DateTime Function() _nowUtc;

  static const _sources = {'AFDJ', 'DanubeHIS', 'DanubeFIS'};
  static const _deltaMethods = {
    'provider_reported',
    'computed_same_source',
    'unavailable',
  };
  static const _qualities = {
    'valid',
    'partial',
    'stale',
    'provider_error',
    'unknown',
  };

  @override
  Future<SnapshotWriteResult> writeIfAbsent(
    DailyWaterSnapshotPayload payload,
  ) async {
    validatePayload(payload);
    await _ensureStationExists(payload.stationId);

    final existing = await _readSnapshots(payload);
    if (existing.length > 1) {
      throw const SnapshotWriteException(
        'Snapshot integrity anomaly: more than one row exists for this station and observation date.',
      );
    }
    if (existing.length == 1) return _mergeAndWrite(existing.single, payload);

    final inserted = await _insert(payload);
    if (_differingFields(payload.toJson(), inserted).isNotEmpty) {
      throw const SnapshotWriteException(
        'Snapshot insert returned data that differs from the requested contract fields.',
      );
    }

    final readBack = await _readSnapshots(payload);
    if (readBack.length != 1) {
      throw const SnapshotWriteException(
        'Snapshot read-back integrity check did not return exactly one row.',
      );
    }
    if (_differingFields(payload.toJson(), readBack.single).isNotEmpty) {
      throw const SnapshotWriteException(
        'Snapshot read-back differs from the requested contract fields.',
      );
    }
    return const SnapshotWriteResult.inserted();
  }

  Future<SnapshotWriteResult> _mergeAndWrite(
    Map<String, Object?> existingRow,
    DailyWaterSnapshotPayload incoming,
  ) async {
    final existing = _payloadFromRow(existingRow);
    validatePayload(existing);
    final merge = const DailyWaterSnapshotMerger().merge(
      existing: existing,
      incoming: incoming,
      nowUtc: _nowUtc().toUtc(),
    );
    switch (merge.outcome) {
      case DailyWaterSnapshotMergeOutcome.identicalNoOp:
        return const SnapshotWriteResult.alreadyExists();
      case DailyWaterSnapshotMergeOutcome.conflictRefused:
        throw SnapshotWriteException(
          'Same-day snapshot merge refused. Conflicting fields: '
          '${merge.conflictingFields.join(', ')}.',
        );
      case DailyWaterSnapshotMergeOutcome.improvedUpdate:
        final changes = _changedFields(
          existing.toJson(),
          merge.payload.toJson(),
        );
        if (changes.isEmpty) return const SnapshotWriteResult.alreadyExists();
        final updatedAt = existingRow['updated_at']?.toString();
        if (updatedAt == null || DateTime.tryParse(updatedAt) == null) {
          throw const SnapshotWriteException(
            'Snapshot read did not include a valid updated_at concurrency value.',
          );
        }
        final patched = await _patch(
          payload: incoming,
          desired: merge.payload,
          updatedAt: updatedAt,
          changes: changes,
        );
        if (patched.isEmpty) {
          return _resolveConcurrentPatchResult(incoming, merge.payload);
        }
        if (patched.length != 1) {
          throw const SnapshotWriteException(
            'Snapshot PATCH did not return exactly one updated row.',
          );
        }
        final patchDifferences = _differingFields(
          merge.payload.toJson(),
          patched.single,
        );
        if (patchDifferences.isNotEmpty) {
          throw SnapshotWriteException(
            'Snapshot PATCH returned data that differs from the merged contract fields: '
            '${patchDifferences.join(', ')}.',
          );
        }
        final readBack = await _readSnapshots(incoming);
        if (readBack.length != 1) {
          throw const SnapshotWriteException(
            'Snapshot PATCH read-back integrity check did not return exactly one row.',
          );
        }
        if (_differingFields(
          merge.payload.toJson(),
          readBack.single,
        ).isNotEmpty) {
          throw const SnapshotWriteException(
            'Snapshot PATCH read-back differs from the merged contract fields.',
          );
        }
        return const SnapshotWriteResult.updated();
    }
  }

  Future<SnapshotWriteResult> _resolveConcurrentPatchResult(
    DailyWaterSnapshotPayload lookup,
    DailyWaterSnapshotPayload desired,
  ) async {
    final current = await _readSnapshots(lookup);
    if (current.length == 1 &&
        _differingFields(desired.toJson(), current.single).isEmpty) {
      return const SnapshotWriteResult.alreadyExists();
    }
    throw const SnapshotWriteException(
      'Concurrent snapshot update conflict; no automatic PATCH retry was attempted.',
    );
  }

  static void validatePayload(DailyWaterSnapshotPayload payload) {
    if (payload.stationId.trim().isEmpty) {
      throw const SnapshotWriteException(
        'Invalid snapshot payload: station_id is required.',
      );
    }
    if (!_isIsoDate(payload.observationDate)) {
      throw const SnapshotWriteException(
        'Invalid snapshot payload: observation_date must use YYYY-MM-DD.',
      );
    }
    _validatePairing('level', [
      payload.levelCm,
      payload.levelSource,
      payload.levelMeasuredAt,
    ]);
    _validateSource('level_source', payload.levelSource);
    _validateSource('delta_source', payload.deltaSource);
    if (!_deltaMethods.contains(payload.deltaMethod)) {
      throw const SnapshotWriteException(
        'Invalid snapshot payload: delta_method.',
      );
    }
    if (!_qualities.contains(payload.quality)) {
      throw const SnapshotWriteException('Invalid snapshot payload: quality.');
    }
    _validateDeltaPairing(payload);
    for (final value in [payload.levelCm, payload.dailyDeltaCm]) {
      if (value != null && !value.isFinite) {
        throw const SnapshotWriteException(
          'Invalid snapshot payload: numeric values must be finite.',
        );
      }
    }
  }

  static bool _isIsoDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  static void _validatePairing(String label, List<Object?> fields) {
    final allNull = fields.every((field) => field == null);
    final allPresent = fields.every((field) => field != null);
    if (!allNull && !allPresent) {
      throw SnapshotWriteException('Invalid snapshot payload: $label pairing.');
    }
  }

  static void _validateSource(String field, String? value) {
    if (value != null && !_sources.contains(value)) {
      throw SnapshotWriteException('Invalid snapshot payload: $field.');
    }
  }

  static void _validateDeltaPairing(DailyWaterSnapshotPayload payload) {
    final hasValue = payload.dailyDeltaCm != null;
    final hasSource = payload.deltaSource != null;
    final hasMeasuredAt = payload.deltaMeasuredAt != null;
    final hasBase = payload.deltaBaseMeasuredAt != null;
    final valid = switch (payload.deltaMethod) {
      'unavailable' => !hasValue && !hasSource && !hasMeasuredAt && !hasBase,
      'provider_reported' => hasValue && hasSource && hasMeasuredAt && !hasBase,
      'computed_same_source' =>
        hasValue && hasSource && hasMeasuredAt && hasBase,
      _ => false,
    };
    if (!valid) {
      throw const SnapshotWriteException(
        'Invalid snapshot payload: delta pairing.',
      );
    }
  }

  Future<void> _ensureStationExists(String stationId) async {
    final response = await _get(
      'station verification',
      _endpoint('stations', {'select': 'id', 'id': 'eq.$stationId'}),
      stationId: stationId,
    );
    final rows = _decodeRows(response, 'station verification');
    if (rows.length != 1) {
      throw const SnapshotWriteException(
        'Remote station was not found or is not uniquely identifiable.',
      );
    }
  }

  Future<List<Map<String, Object?>>> _readSnapshots(
    DailyWaterSnapshotPayload payload,
  ) async {
    final response = await _get(
      'snapshot read',
      _endpoint('daily_water_snapshots', {
        'select': '${_contractFields.join(',')},updated_at',
        'station_id': 'eq.${payload.stationId}',
        'observation_date': 'eq.${payload.observationDate}',
      }),
      stationId: payload.stationId,
    );
    return _decodeRows(response, 'snapshot read');
  }

  Future<Map<String, Object?>> _insert(
    DailyWaterSnapshotPayload payload,
  ) async {
    final response = await _post(
      'snapshot insert',
      _endpoint('daily_water_snapshots', {'select': _contractFields.join(',')}),
      jsonEncode(payload.toJson()),
      stationId: payload.stationId,
    );
    final rows = _decodeRows(response, 'snapshot insert');
    if (rows.length != 1) {
      throw const SnapshotWriteException(
        'Snapshot insert did not return exactly one created row.',
      );
    }
    return rows.single;
  }

  Future<List<Map<String, Object?>>> _patch({
    required DailyWaterSnapshotPayload payload,
    required DailyWaterSnapshotPayload desired,
    required String updatedAt,
    required Map<String, Object?> changes,
  }) async {
    final response = await _patchRequest(
      'snapshot PATCH',
      _endpoint('daily_water_snapshots', {
        'select': _contractFields.join(','),
        'station_id': 'eq.${payload.stationId}',
        'observation_date': 'eq.${payload.observationDate}',
        'updated_at': 'eq.$updatedAt',
      }),
      jsonEncode(changes),
      stationId: desired.stationId,
    );
    return _decodeRows(response, 'snapshot PATCH');
  }

  Future<http.Response> _get(
    String operation,
    Uri uri, {
    String? stationId,
  }) async {
    try {
      final response = await _client.get(uri, headers: _headers);
      _ensureSuccess(operation, response);
      return response;
    } on SnapshotWriteException {
      rethrow;
    } on Object catch (error) {
      throw _transportException(operation, error, stationId);
    }
  }

  Future<http.Response> _post(
    String operation,
    Uri uri,
    String body, {
    String? stationId,
  }) async {
    try {
      final response = await _client.post(
        uri,
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: body,
      );
      _ensureSuccess(operation, response);
      return response;
    } on SnapshotWriteException {
      rethrow;
    } on Object catch (error) {
      throw _transportException(operation, error, stationId);
    }
  }

  Future<http.Response> _patchRequest(
    String operation,
    Uri uri,
    String body, {
    String? stationId,
  }) async {
    try {
      final response = await _client.patch(
        uri,
        headers: {..._headers, 'Prefer': 'return=representation'},
        body: body,
      );
      _ensureSuccess(operation, response);
      return response;
    } on SnapshotWriteException {
      rethrow;
    } on Object catch (error) {
      throw _transportException(operation, error, stationId);
    }
  }

  SnapshotWriteException _transportException(
    String operation,
    Object error,
    String? stationId,
  ) {
    final context = stationId == null ? '' : 'station_id=$stationId; ';
    return SnapshotWriteException(
      '$context${_operationLabel(operation)} transport failure '
      '(${error.runtimeType}): ${_sanitisedTransportMessage(error)}.',
    );
  }

  void _ensureSuccess(String operation, http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _sanitisedResponseMessage(response.body);
      throw SnapshotWriteException(
        '${_operationLabel(operation)} request failed '
        '(HTTP ${response.statusCode}): $message.',
      );
    }
  }

  String _sanitisedResponseMessage(String responseBody) {
    String message = responseBody;
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map) {
        for (final field in ['message', 'error', 'details', 'hint']) {
          final value = decoded[field];
          if (value is String && value.trim().isNotEmpty) {
            message = value;
            break;
          }
        }
      }
    } on Object {
      // The short normalized body below is the safe fallback.
    }
    final sanitized = message
        .replaceAll(_secretKey, '[redacted]')
        .replaceAll(
          RegExp(r'https?://\S+', caseSensitive: false),
          '[redacted-url]',
        )
        .replaceAll(
          RegExp(
            r'authorization\s*[:=]\s*\S+(?:\s+\S+)?',
            caseSensitive: false,
          ),
          'Authorization: [redacted]',
        )
        .replaceAll(
          RegExp(r'apikey\s*[:=]\s*\S+', caseSensitive: false),
          'apikey: [redacted]',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) return 'No response message';
    return sanitized.length <= 160
        ? sanitized
        : '${sanitized.substring(0, 160)}…';
  }

  String _sanitisedTransportMessage(Object error) {
    final type = error.runtimeType.toString();
    final message = error.toString().replaceFirst(
      RegExp('^${RegExp.escape(type)}:\\s*'),
      '',
    );
    return _sanitiseShortMessage(message);
  }

  String _sanitiseShortMessage(String message) {
    final sanitized = message
        .replaceAll(_secretKey, '[redacted]')
        .replaceAll(
          RegExp(r'https?://\S+', caseSensitive: false),
          '[redacted-url]',
        )
        .replaceAll(
          RegExp(
            r'authorization\s*[:=]\s*\S+(?:\s+\S+)?',
            caseSensitive: false,
          ),
          'Authorization: [redacted]',
        )
        .replaceAll(
          RegExp(r'apikey\s*[:=]\s*\S+', caseSensitive: false),
          'apikey: [redacted]',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (sanitized.isEmpty) return 'No response message';
    return sanitized.length <= 160
        ? sanitized
        : '${sanitized.substring(0, 160)}…';
  }

  static String _operationLabel(String operation) =>
      '${operation[0].toUpperCase()}${operation.substring(1)}';

  List<Map<String, Object?>> _decodeRows(
    http.Response response,
    String operation,
  ) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException();
      return decoded
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList(growable: false);
    } on Object {
      throw SnapshotWriteException('$operation returned an invalid response.');
    }
  }

  Uri _endpoint(String table, Map<String, String> queryParameters) {
    final base = Uri.parse(_supabaseUrl);
    return base.replace(
      path: '/rest/v1/$table',
      queryParameters: queryParameters,
    );
  }

  Map<String, String> get _headers => {
    'apikey': _secretKey,
    'Content-Type': 'application/json',
  };

  static List<String> _differingFields(
    Map<String, Object?> expected,
    Map<String, Object?> actual,
  ) => _contractFields
      .where(
        (field) =>
            _normalise(field, expected[field]) !=
            _normalise(field, actual[field]),
      )
      .toList(growable: false);

  static Map<String, Object?> _changedFields(
    Map<String, Object?> existing,
    Map<String, Object?> desired,
  ) => {
    for (final field in _contractFields)
      if (_normalise(field, existing[field]) !=
          _normalise(field, desired[field]))
        field: desired[field],
  };

  static DailyWaterSnapshotPayload _payloadFromRow(Map<String, Object?> row) {
    DateTime? timestamp(String field) {
      final value = row[field];
      if (value == null) return null;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed == null) {
        throw SnapshotWriteException(
          'Snapshot read returned an invalid $field value.',
        );
      }
      return parsed.toUtc();
    }

    String requiredString(String field) {
      final value = row[field]?.toString();
      if (value == null || value.isEmpty) {
        throw SnapshotWriteException('Snapshot read omitted $field.');
      }
      return value;
    }

    int? integer(String field) {
      final value = row[field];
      if (value == null) return null;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    return DailyWaterSnapshotPayload(
      stationId: requiredString('station_id'),
      observationDate: requiredString('observation_date'),
      levelCm: integer('level_cm'),
      levelSource: row['level_source']?.toString(),
      levelMeasuredAt: timestamp('level_measured_at'),
      dailyDeltaCm: integer('daily_delta_cm'),
      deltaSource: row['delta_source']?.toString(),
      deltaMeasuredAt: timestamp('delta_measured_at'),
      deltaBaseMeasuredAt: timestamp('delta_base_measured_at'),
      deltaMethod: requiredString('delta_method'),
      quality: requiredString('quality'),
    );
  }

  static Object? _normalise(String field, Object? value) {
    if (value == null) return null;
    if (field.endsWith('_at')) {
      final parsed = DateTime.tryParse(value.toString());
      return parsed?.toUtc().toIso8601String() ?? value;
    }
    if (field == 'level_cm' || field == 'daily_delta_cm') {
      return value is num ? value.toInt() : value;
    }
    return value;
  }

  @override
  void close() => _client.close();
}
