import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260810220000_fix_water_freshness_contract.sql';

  test('new migration separates AFDJ measurement and freshness timestamps', () {
    final sql = File(migrationPath).readAsStringSync();

    expect(sql, contains('observed_at_precision = \'date\''));
    expect(sql, contains('source_changed_at timestamptz'));
    expect(sql, contains('freshness_at timestamptz'));
    expect(
      sql,
      contains(
        'coalesce(observation.source_changed_at, observation.fetched_at)',
      ),
    );
    expect(
      sql,
      contains("when staging.exact_observed_at is not null then 'exact'"),
    );
    expect(sql, contains("else 'relative'"));
  });

  test('latest arbitration remains fresh first and AFDJ before HIS/FIS', () {
    final sql = File(migrationPath).readAsStringSync();

    expect(sql, contains('candidate.candidate_is_stale asc nulls last'));
    expect(sql, contains('candidate.source_priority asc'));
    expect(sql, contains("when 'AFDJ' then 1"));
    expect(sql, contains("when 'DanubeHIS' then 2"));
    expect(sql, contains("when 'DanubeFIS' then 3"));
    expect(sql, isNot(contains('insert into public.daily_water_snapshots')));
  });
}
