import 'dart:convert';

import 'package:fishtrack/services/community_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'https://verification.test';
const _anonKey = 'test-anon-key';
const _userId = '11111111-1111-4111-8111-111111111111';
const _reportId = '22222222-2222-4222-8222-222222222222';

void main() {
  test(
    'stillValid sends only the authenticated verification RPC contract',
    () async {
      late http.Request verificationRequest;
      var authUserRequestCount = 0;
      final client = await _authenticatedClient((request) async {
        if (request.url.path == '/auth/v1/user') {
          authUserRequestCount++;
          return _authUserResponse();
        }
        if (request.url.path == '/rest/v1/rpc/submit_report_verification') {
          verificationRequest = request;
          return http.Response('', 204, request: request);
        }
        throw StateError(
          'Unexpected request: ${request.method} ${request.url}',
        );
      });
      addTearDown(client.dispose);

      await CommunityService(
        client: client,
      ).verifyReport(_reportId, ReportVerification.stillValid);

      expect(authUserRequestCount, 1);
      expect(verificationRequest.method, 'POST');
      expect(
        verificationRequest.url.path,
        '/rest/v1/rpc/submit_report_verification',
      );
      expect(
        verificationRequest.url.queryParameters,
        isNot(contains('on_conflict')),
      );

      final body = jsonDecode(verificationRequest.body) as Map<String, dynamic>;
      expect(body, {'p_report_id': _reportId, 'p_is_valid': true});
      expect(body, isNot(contains('user_id')));
      expect(body, isNot(contains('created_at')));
    },
  );

  test('noLongerValid sends is_valid false', () async {
    late http.Request verificationRequest;
    final client = await _authenticatedClient((request) async {
      if (request.url.path == '/auth/v1/user') {
        return _authUserResponse();
      }
      if (request.url.path == '/rest/v1/rpc/submit_report_verification') {
        verificationRequest = request;
        return http.Response('', 204, request: request);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(client.dispose);

    await CommunityService(
      client: client,
    ).verifyReport(_reportId, ReportVerification.noLongerValid);

    final body = jsonDecode(verificationRequest.body) as Map<String, dynamic>;
    expect(body, {'p_report_id': _reportId, 'p_is_valid': false});
    expect(body, isNot(contains('user_id')));
    expect(body, isNot(contains('created_at')));
  });

  test('unauthenticated verification fails before the REST request', () async {
    var verificationRequestCount = 0;
    final client = SupabaseClient(
      _supabaseUrl,
      _anonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path == '/rest/v1/rpc/submit_report_verification') {
          verificationRequestCount++;
        }
        throw StateError(
          'Unauthenticated verification issued a request: ${request.url}',
        );
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      CommunityService(
        client: client,
      ).verifyReport(_reportId, ReportVerification.stillValid),
      throwsA(
        isA<CommunityException>().having(
          (error) => error.code,
          'code',
          CommunityErrorCode.sessionExpired,
        ),
      ),
    );
    expect(verificationRequestCount, 0);
  });
}

Future<SupabaseClient> _authenticatedClient(
  Future<http.Response> Function(http.Request request) handler,
) async {
  final client = SupabaseClient(
    _supabaseUrl,
    _anonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );
  final jwt = _unexpiredJwt();
  final callback = Uri.parse(
    '$_supabaseUrl/callback'
    '#access_token=${Uri.encodeQueryComponent(jwt)}'
    '&expires_in=3600'
    '&refresh_token=test-refresh-token'
    '&token_type=bearer',
  );
  await client.auth.getSessionFromUrl(callback);
  return client;
}

String _unexpiredJwt() {
  final issuedAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  String encodePart(Map<String, Object> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

  return '${encodePart({'alg': 'none', 'typ': 'JWT'})}.'
      '${encodePart({'sub': _userId, 'aud': 'authenticated', 'role': 'authenticated', 'iat': issuedAt, 'exp': issuedAt + 3600})}.'
      'local-test-signature';
}

http.Response _authUserResponse() {
  final now = DateTime.now().toUtc().toIso8601String();
  return http.Response(
    jsonEncode({
      'id': _userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'verification@example.test',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'created_at': now,
      'updated_at': now,
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}
