import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260723200000_report_verification_counts.sql';

void main() {
  late String sql;

  setUpAll(() async {
    sql = await File(_migrationPath).readAsString();
  });

  test('defines a secured trigger function with a fixed search path', () {
    expect(
      sql,
      contains(
        RegExp(
          r'create\s+or\s+replace\s+function\s+'
          r'public\.sync_report_verification_counts\s*\(\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(sql, contains(RegExp(r'returns\s+trigger', caseSensitive: false)));
    expect(sql, contains(RegExp(r'language\s+plpgsql', caseSensitive: false)));
    expect(sql, contains(RegExp(r'security\s+definer', caseSensitive: false)));
    expect(
      sql,
      contains(RegExp(r'set\s+search_path\s*=\s*public', caseSensitive: false)),
    );
  });

  test('synchronizes both counters from report verifications', () {
    expect(sql, contains('still_valid_count'));
    expect(sql, contains('no_longer_valid_count'));
    expect(
      sql,
      contains(
        RegExp(r'from\s+public\.report_verifications', caseSensitive: false),
      ),
    );
    expect(
      sql,
      contains(RegExp(r'is_valid\s+is\s+true', caseSensitive: false)),
    );
    expect(
      sql,
      contains(RegExp(r'is_valid\s+is\s+false', caseSensitive: false)),
    );
  });

  test('handles every vote mutation and report id changes', () {
    expect(
      sql,
      contains(
        RegExp(
          r'after\s+insert\s+or\s+update\s+or\s+delete\s+'
          r'on\s+public\.report_verifications',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      contains(
        RegExp(
          r'old\.report_id\s+is\s+distinct\s+from\s+new\.report_id',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      contains(
        RegExp(
          r'execute\s+function\s+'
          r'public\.sync_report_verification_counts\s*\(\s*\)',
          caseSensitive: false,
        ),
      ),
    );
  });

  test('backfills reports and revokes direct client execution', () {
    final reportCounterUpdates = RegExp(
      r'update\s+public\.reports\s+as\s+report',
      caseSensitive: false,
    ).allMatches(sql);
    expect(
      reportCounterUpdates.length,
      greaterThanOrEqualTo(2),
      reason: 'Expected both trigger recalculation and migration backfill.',
    );
    expect(
      sql,
      contains(
        RegExp(
          r'revoke\s+all\s+privileges\s+on\s+function\s+'
          r'public\.sync_report_verification_counts\s*\(\s*\)\s+'
          r'from\s+public\s*,\s*anon\s*,\s*authenticated',
          caseSensitive: false,
        ),
      ),
    );
  });

  test('defines the authenticated verification RPC contract', () {
    final rpc = _rpcDefinition(sql);
    final signature = rpc.group(1)!;
    final definition = rpc.group(0)!;

    expect(
      signature,
      contains(
        RegExp(
          r'p_report_id\s+uuid\s*,\s*p_is_valid\s+boolean',
          caseSensitive: false,
        ),
      ),
    );
    expect(signature, isNot(contains(RegExp(r'\buser_id\b'))));
    expect(signature, isNot(contains(RegExp(r'\bcreated_at\b'))));
    expect(
      definition,
      contains(RegExp(r'language\s+plpgsql', caseSensitive: false)),
    );
    expect(
      definition,
      contains(RegExp(r'security\s+definer', caseSensitive: false)),
    );
    expect(
      definition,
      contains(
        RegExp(
          r'set\s+search_path\s*=\s*public\s*,\s*pg_temp',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      definition,
      contains(RegExp(r'auth\.uid\s*\(\s*\)', caseSensitive: false)),
    );
    expect(definition, contains(RegExp(r"errcode\s*=\s*'42501'")));
    expect(
      definition,
      contains(RegExp(r'p_report_id\s+is\s+null', caseSensitive: false)),
    );
    expect(
      definition,
      contains(RegExp(r'p_is_valid\s+is\s+null', caseSensitive: false)),
    );
    expect(
      RegExp(r"errcode\s*=\s*'22004'").allMatches(definition),
      hasLength(2),
    );
    expect(
      definition,
      contains(
        RegExp(
          r'on\s+conflict\s*\(\s*report_id\s*,\s*user_id\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      definition,
      contains(
        RegExp(r'is_valid\s*=\s*excluded\.is_valid', caseSensitive: false),
      ),
    );
    expect(
      definition,
      contains(RegExp(r'created_at\s*=\s*now\s*\(\s*\)', caseSensitive: false)),
    );
    expect(
      RegExp(
        r'now\s*\(\s*\)',
        caseSensitive: false,
      ).allMatches(definition).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('exposes the verification RPC only to authenticated users', () {
    expect(
      sql,
      contains(
        RegExp(
          r'revoke\s+all\s+privileges\s+on\s+function\s+'
          r'public\.submit_report_verification\s*'
          r'\(\s*uuid\s*,\s*boolean\s*\)\s+'
          r'from\s+public\s*,\s*anon\s*,\s*authenticated',
          caseSensitive: false,
        ),
      ),
    );
    final executeGrants = RegExp(
      r'grant\s+execute\s+on\s+function\s+'
      r'public\.submit_report_verification\s*'
      r'\(\s*uuid\s*,\s*boolean\s*\)\s+to\s+([^;]+);',
      caseSensitive: false,
    ).allMatches(sql).toList();
    expect(executeGrants, hasLength(1));
    expect(
      executeGrants.single.group(1)!.trim().toLowerCase(),
      'authenticated',
    );
  });

  test('limits reports ACLs to authenticated select and approved insert', () {
    expect(sql, contains(_revokeAllTablePrivileges('reports')));

    final reportGrants = _tableGrants(sql, 'reports');
    expect(reportGrants, hasLength(2));
    for (final grant in reportGrants) {
      expect(grant.group(2)!.trim().toLowerCase(), 'authenticated');
    }
    expect(
      reportGrants.where(
        (grant) => grant.group(1)!.trim().toLowerCase() == 'select',
      ),
      hasLength(1),
    );
    final insertGrant = reportGrants.singleWhere(
      (grant) => RegExp(
        r'^insert\s*\(',
        caseSensitive: false,
      ).hasMatch(grant.group(1)!.trim()),
    );
    final insertColumns =
        RegExp(r'^insert\s*\(([\s\S]*?)\)$', caseSensitive: false)
            .firstMatch(insertGrant.group(1)!.trim())!
            .group(1)!
            .split(',')
            .map((column) => column.trim().toLowerCase())
            .toSet();
    expect(
      insertColumns,
      unorderedEquals({
        'user_id',
        'type',
        'category',
        'description',
        'image_url',
        'latitude',
        'longitude',
        'created_at',
        'expires_at',
        'spam_score',
        'is_suspicious',
        'spam_reason',
        'image_hash',
      }),
    );
    expect(insertColumns, isNot(contains('id')));
    expect(insertColumns, isNot(contains('still_valid_count')));
    expect(insertColumns, isNot(contains('no_longer_valid_count')));
    expect(
      reportGrants.any((grant) {
        final privilege = grant.group(1)!.trim().toLowerCase();
        return privilege.startsWith('update') ||
            privilege.startsWith('delete') ||
            privilege.startsWith('truncate') ||
            privilege.startsWith('trigger') ||
            privilege.startsWith('references') ||
            privilege.startsWith('maintain');
      }),
      isFalse,
    );
  });

  test('removes all direct mobile access to report verifications', () {
    expect(sql, contains(_revokeAllTablePrivileges('report_verifications')));
    expect(_tableGrants(sql, 'report_verifications'), isEmpty);
  });
}

RegExpMatch _rpcDefinition(String sql) {
  final match = RegExp(
    r'create\s+or\s+replace\s+function\s+'
    r'public\.submit_report_verification\s*'
    r'\(([\s\S]*?)\)\s*returns\s+void[\s\S]*?\$\$\s*;',
    caseSensitive: false,
  ).firstMatch(sql);
  expect(match, isNotNull, reason: 'Verification RPC definition is missing.');
  return match!;
}

RegExp _revokeAllTablePrivileges(String table) => RegExp(
  'revoke\\s+all\\s+privileges\\s+on\\s+table\\s+'
  'public\\.$table\\s+from\\s+'
  'public\\s*,\\s*anon\\s*,\\s*authenticated',
  caseSensitive: false,
);

List<RegExpMatch> _tableGrants(String sql, String table) => RegExp(
  'grant\\s+([^;]+?)\\s+on\\s+table\\s+'
  'public\\.$table\\s+to\\s+([^;]+);',
  caseSensitive: false,
).allMatches(sql).toList();
