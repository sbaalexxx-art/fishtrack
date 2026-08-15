import 'dart:convert';
import 'dart:io';

import 'package:fishtrack/services/community_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'https://community-feed.test';
const _anonKey = 'test-anon-key';
const _reportId = '22222222-2222-4222-8222-222222222222';
const _userId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('keeps real reports when optional community queries fail', () async {
    final client = _client((request) async {
      switch (request.url.path) {
        case '/rest/v1/reports':
          return _jsonResponse(request, [_reportRow()]);
        case '/rest/v1/catches':
        case '/rest/v1/profiles':
        case '/rest/v1/user_reputation':
          return _errorResponse(request);
        default:
          throw StateError(
            'Unexpected request: ${request.method} ${request.url}',
          );
      }
    });
    addTearDown(client.dispose);

    final result = await CommunityService(
      client: client,
    ).getFeedResult(forceRefresh: true);

    expect(result.isStaleFallback, isFalse);
    expect(result.value, hasLength(1));
    expect(result.value.single.id, _reportId);
    expect(result.value.single.type, CommunityPostType.report);
  });

  test('does not retain an empty feed as a fresh cache hit', () async {
    var reportRequestCount = 0;
    final client = _client((request) async {
      switch (request.url.path) {
        case '/rest/v1/reports':
          reportRequestCount++;
          return _jsonResponse(
            request,
            reportRequestCount == 1 ? const [] : [_reportRow()],
          );
        case '/rest/v1/catches':
        case '/rest/v1/profiles':
        case '/rest/v1/user_reputation':
          return _jsonResponse(request, const []);
        default:
          throw StateError(
            'Unexpected request: ${request.method} ${request.url}',
          );
      }
    });
    addTearDown(client.dispose);
    final service = CommunityService(client: client);

    final empty = await service.getFeedResult(forceRefresh: true);
    final refreshed = await service.getFeedResult();

    expect(empty.value, isEmpty);
    expect(reportRequestCount, 2);
    expect(refreshed.value.map((post) => post.id), [_reportId]);
  });

  test('keeps a non-empty last-known-good feed while offline', () async {
    var offline = false;
    final client = _client((request) async {
      if (request.url.path == '/rest/v1/reports') {
        if (offline) throw const SocketException('offline');
        return _jsonResponse(request, [_reportRow()]);
      }
      if (request.url.path == '/rest/v1/catches') {
        return _jsonResponse(request, const []);
      }
      if (request.url.path == '/rest/v1/profiles' ||
          request.url.path == '/rest/v1/user_reputation') {
        return _jsonResponse(request, const []);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.dispose);
    final service = CommunityService(client: client);

    final online = await service.getFeedResult(forceRefresh: true);
    offline = true;
    final fallback = await service.getFeedResult(forceRefresh: true);

    expect(online.value.map((post) => post.id), [_reportId]);
    expect(fallback.isStaleFallback, isTrue);
    expect(fallback.value.map((post) => post.id), [_reportId]);
  });
}

SupabaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => SupabaseClient(
  _supabaseUrl,
  _anonKey,
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient(handler),
);

Map<String, Object?> _reportRow() {
  final now = DateTime.now().toUtc();
  return {
    'id': _reportId,
    'user_id': _userId,
    'type': 'Fish activity',
    'category': 'fishActivity',
    'description': 'Active report',
    'created_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    'expires_at': now.add(const Duration(hours: 1)).toIso8601String(),
    'still_valid_count': 0,
    'no_longer_valid_count': 0,
    'spam_score': 0,
    'is_suspicious': false,
  };
}

http.Response _jsonResponse(http.Request request, Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
  request: request,
);

http.Response _errorResponse(http.Request request) => http.Response(
  jsonEncode({
    'code': 'TEST_ERROR',
    'message': 'Optional endpoint unavailable',
    'details': null,
    'hint': null,
  }),
  500,
  headers: const {'content-type': 'application/json'},
  request: request,
);
