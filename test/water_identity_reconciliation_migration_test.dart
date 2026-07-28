import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260728110000_water_identity_reconciliation.sql';

void main() {
  late String sql;

  setUpAll(() async {
    sql = await File(_migrationPath).readAsString();
  });

  test('defines the canonical water identity tables', () {
    for (final table in <String>[
      'water_bodies',
      'water_station_source_mappings',
      'water_body_source_mappings',
      'water_entity_relations',
    ]) {
      expect(
        sql,
        contains(
          RegExp(
            'create\\s+table\\s+if\\s+not\\s+exists\\s+public\\.$table',
            caseSensitive: false,
          ),
        ),
        reason: 'Missing canonical table $table.',
      );
    }
  });

  test('supports only approved water body types and branch hierarchy', () {
    expect(
      sql,
      contains(
        RegExp(
          r"type\s+in\s*\(\s*'river'\s*,\s*'branch'\s*,\s*"
          r"'reservoir'\s*,\s*'lake'\s*\)",
          caseSensitive: false,
        ),
      ),
    );
    expect(sql, contains('parent_water_body_id uuid'));
    expect(
      sql,
      contains(
        RegExp(
          r'foreign\s+key\s*\(\s*parent_water_body_id\s*\)'
          r'\s*references\s+public\.water_bodies\s*\(\s*id\s*\)'
          r'[\s\S]*?on\s+delete\s+restrict',
          caseSensitive: false,
        ),
      ),
    );
    expect(sql, contains('validate_water_body_hierarchy'));
    expect(sql, contains('A branch parent must be a river.'));
  });

  test('adds nullable canonical foreign keys without changing station ids', () {
    for (final table in <String>['stations', 'dams', 'reservoirs']) {
      expect(
        sql,
        contains(
          RegExp(
            'alter\\s+table\\s+public\\.$table\\s+'
            'add\\s+column\\s+if\\s+not\\s+exists\\s+'
            'water_body_id\\s+uuid\\s*;',
            caseSensitive: false,
          ),
        ),
      );
    }

    for (final constraint in <String>[
      'stations_water_body_fkey',
      'dams_water_body_fkey',
      'reservoirs_water_body_fkey',
    ]) {
      expect(sql, contains(constraint));
    }

    expect(
      sql,
      isNot(
        contains(
          RegExp(
            r'alter\s+column\s+water_body_id\s+set\s+not\s+null',
            caseSensitive: false,
          ),
        ),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(
            r'alter\s+table\s+public\.stations[\s\S]*?alter\s+column\s+id',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('seeds one Danube river and four distinct branches', () {
    expect(sql, contains("'ro-danube'"));

    for (final branch in <String>[
      'ro-danube-borcea',
      'ro-danube-chilia',
      'ro-danube-sulina',
      'ro-danube-sfantu-gheorghe',
    ]) {
      expect(sql, contains("'$branch'"));
    }

    expect(
      sql,
      contains(
        RegExp(
          r"if\s*\(\s*select\s+count\(\*\)[\s\S]*?"
          r"type\s*=\s*'branch'[\s\S]*?\)\s*<>\s*4",
          caseSensitive: false,
        ),
      ),
    );
    expect(sql, contains("'branch_of'"));
  });

  test('links exactly the verified 23 snapshot stations to the Danube', () {
    final stationUpdate = RegExp(
      r'update\s+public\.stations\s+as\s+station'
      r'[\s\S]*?set\s+water_body_id\s*=\s*danube\.id'
      r'[\s\S]*?where\s+station\.water_body_id\s+is\s+null'
      r'[\s\S]*?from\s+public\.daily_water_snapshots'
      r'[\s\S]*?;',
      caseSensitive: false,
    ).firstMatch(sql);

    expect(stationUpdate, isNotNull);
    expect(
      stationUpdate!.group(0),
      isNot(
        contains(
          RegExp(
            r'set\s+(id|name|river|level|trend|latitude|longitude|last_update)',
            caseSensitive: false,
          ),
        ),
      ),
    );

    expect(
      sql,
      contains(
        RegExp(
          r'from\s+public\.stations'
          r'[\s\S]*?where\s+water_body_id\s*=\s*danube_id'
          r'[\s\S]*?\)\s*<>\s*23',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      contains(
        RegExp(
          r'from\s+public\.stations'
          r'[\s\S]*?where\s+water_body_id\s+is\s+null'
          r'[\s\S]*?\)\s*<>\s*4',
          caseSensitive: false,
        ),
      ),
    );
  });

  test('keeps legacy branches separate from station identity', () {
    expect(
      sql,
      contains(
        RegExp(
          r"join\s+public\.water_bodies\s+as\s+body"
          r"[\s\S]*?body\.type\s*=\s*'branch'",
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(r'insert\s+into\s+public\.stations', caseSensitive: false),
        ),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(r'delete\s+from\s+public\.stations', caseSensitive: false),
        ),
      ),
    );
  });

  test('allows many source ids to resolve to canonical identities', () {
    expect(
      sql,
      contains(
        RegExp(
          r'unique\s*\(\s*source\s*,\s*country_code\s*,\s*'
          r'source_station_id\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      contains(
        RegExp(
          r'unique\s*\(\s*source\s*,\s*country_code\s*,\s*'
          r'source_water_body_id\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(r'unique\s*\(\s*station_id\s*\)', caseSensitive: false),
        ),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(r'unique\s*\(\s*water_body_id\s*\)', caseSensitive: false),
        ),
      ),
    );
  });

  test('defines referentially safe polymorphic water relations', () {
    expect(sql, contains('num_nonnulls('));
    expect(sql, contains('source_entity_key text generated always as'));
    expect(sql, contains('target_entity_key text generated always as'));
    expect(
      sql,
      contains(
        RegExp(
          r'unique\s*\(\s*relation_type\s*,\s*source_entity_key\s*,\s*'
          r'target_entity_key\s*\)',
          caseSensitive: false,
        ),
      ),
    );

    for (final table in <String>[
      'water_bodies',
      'stations',
      'dams',
      'reservoirs',
    ]) {
      expect(
        sql,
        contains(
          RegExp(
            'references\\s+public\\.$table\\s*\\(\\s*id\\s*\\)'
            '[\\s\\S]*?on\\s+delete\\s+restrict',
            caseSensitive: false,
          ),
        ),
      );
    }
  });

  test('does not import the ANAR catalog or alter snapshots', () {
    for (final table in <String>[
      'dams',
      'reservoirs',
      'dam_reservoir_relations',
    ]) {
      expect(
        sql,
        isNot(
          contains(
            RegExp('insert\\s+into\\s+public\\.$table', caseSensitive: false),
          ),
        ),
      );
    }

    for (final operation in <String>[
      'insert\\s+into',
      'update',
      'delete\\s+from',
      'truncate',
      'alter\\s+table',
    ]) {
      expect(
        sql,
        isNot(
          contains(
            RegExp(
              '$operation\\s+public\\.daily_water_snapshots',
              caseSensitive: false,
            ),
          ),
        ),
      );
    }

    expect(
      sql,
      contains(
        RegExp(
          r'create\s+temporary\s+table\s+w4d2_runtime_baseline',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      sql,
      contains(RegExp(r'if\s+snapshot_count\s*<\s*178', caseSensitive: false)),
    );
    expect(
      sql,
      contains(
        RegExp(
          r'count\(\*\)[\s\S]*?from\s+public\.daily_water_snapshots'
          r'[\s\S]*?<>\s*baseline_snapshot_count',
          caseSensitive: false,
        ),
      ),
    );
    expect(sql, contains('snapshot count changed'));
  });

  test('keeps source mappings and ANAR catalog empty in W4D-2', () {
    for (final table in <String>[
      'water_station_source_mappings',
      'water_body_source_mappings',
      'dams',
      'reservoirs',
      'dam_reservoir_relations',
    ]) {
      expect(
        sql,
        contains(
          RegExp(
            'select\\s+count\\(\\*\\)\\s+from\\s+public\\.$table'
            '\\s*\\)\\s*<>\\s*0',
            caseSensitive: false,
          ),
        ),
      );
    }
  });

  test('enables RLS and withholds mapping tables from clients', () {
    for (final table in <String>[
      'water_bodies',
      'water_station_source_mappings',
      'water_body_source_mappings',
      'water_entity_relations',
    ]) {
      expect(
        sql,
        contains(
          RegExp(
            'alter\\s+table\\s+public\\.$table\\s+'
            'enable\\s+row\\s+level\\s+security',
            caseSensitive: false,
          ),
        ),
      );
    }

    for (final table in <String>[
      'water_station_source_mappings',
      'water_body_source_mappings',
    ]) {
      expect(sql, contains(_revokeAllTablePrivileges(table)));
      expect(_clientTableGrants(sql, table), isEmpty);
    }
  });

  test('replaces full catalog reads with column-restricted grants', () {
    for (final table in <String>[
      'dams',
      'reservoirs',
      'dam_reservoir_relations',
      'water_bodies',
      'water_entity_relations',
    ]) {
      expect(sql, contains(_revokeAllTablePrivileges(table)));

      expect(
        sql,
        isNot(
          contains(
            RegExp(
              'grant\\s+select\\s+on\\s+table\\s+public\\.$table'
              '\\s+to\\s+(anon|authenticated)',
              caseSensitive: false,
            ),
          ),
        ),
      );

      expect(
        sql,
        contains(
          RegExp(
            'grant\\s+select\\s*\\([\\s\\S]*?\\)'
            '\\s*on\\s+table\\s+public\\.$table'
            '\\s*to\\s+anon\\s*,\\s*authenticated',
            caseSensitive: false,
          ),
        ),
      );
    }
  });

  test('defines security-invoker restricted public views', () {
    for (final view in <String>[
      'water_bodies_public',
      'water_stations_public',
      'water_dams_public',
      'water_reservoirs_public',
      'dam_reservoir_relations_public',
      'water_entity_relations_public',
    ]) {
      expect(
        sql,
        contains(
          RegExp(
            'create\\s+or\\s+replace\\s+view\\s+public\\.$view'
            '\\s+with\\s*\\(\\s*security_invoker\\s*=\\s*true'
            '[\\s\\S]*?security_barrier\\s*=\\s*true\\s*\\)',
            caseSensitive: false,
          ),
        ),
      );
      expect(
        sql,
        contains(
          RegExp(
            'grant\\s+select\\s+on\\s+table\\s+public\\.$view'
            '\\s+to\\s+anon\\s*,\\s*authenticated',
            caseSensitive: false,
          ),
        ),
      );
    }
  });

  test('never exposes owner, raw payload or internal evidence publicly', () {
    final damsView = _viewDefinition(sql, 'water_dams_public');
    final reservoirsView = _viewDefinition(sql, 'water_reservoirs_public');
    final relationsView = _viewDefinition(sql, 'water_entity_relations_public');
    final damRelationsView = _viewDefinition(
      sql,
      'dam_reservoir_relations_public',
    );

    for (final definition in <String>[
      damsView,
      reservoirsView,
      relationsView,
      damRelationsView,
    ]) {
      expect(
        definition,
        isNot(contains(RegExp(r'\bowner\b', caseSensitive: false))),
      );
      expect(
        definition,
        isNot(contains(RegExp(r'\braw_payload\b', caseSensitive: false))),
      );
      expect(
        definition,
        isNot(contains(RegExp(r'\bevidence\b', caseSensitive: false))),
      );
    }

    final damGrant = _columnGrant(sql, 'dams');
    final reservoirGrant = _columnGrant(sql, 'reservoirs');
    final entityRelationGrant = _columnGrant(sql, 'water_entity_relations');

    expect(damGrant, isNot(contains(RegExp(r'\bowner\b'))));
    expect(damGrant, isNot(contains(RegExp(r'\braw_payload\b'))));
    expect(reservoirGrant, isNot(contains(RegExp(r'\bowner\b'))));
    expect(reservoirGrant, isNot(contains(RegExp(r'\braw_payload\b'))));
    expect(entityRelationGrant, isNot(contains(RegExp(r'\bevidence\b'))));
  });

  test(
    'keeps region id nullable and does not invent a regions foreign key',
    () {
      expect(
        sql,
        contains(RegExp(r'\bregion_id\s+text\b', caseSensitive: false)),
      );
      expect(
        sql,
        isNot(
          contains(
            RegExp(
              r'references\s+public\.(regions|region)',
              caseSensitive: false,
            ),
          ),
        ),
      );
    },
  );
}

RegExp _revokeAllTablePrivileges(String table) => RegExp(
  'revoke\\s+all\\s+privileges\\s+'
  'on\\s+table\\s+public\\.$table\\s+from\\s+'
  'public\\s*,\\s*anon\\s*,\\s*authenticated',
  caseSensitive: false,
);

List<RegExpMatch> _clientTableGrants(String sql, String table) => RegExp(
  'grant\\s+[^;]+?\\s+on\\s+table\\s+public\\.$table'
  '\\s+to\\s+(anon|authenticated)',
  caseSensitive: false,
).allMatches(sql).toList();

String _viewDefinition(String sql, String view) {
  final match = RegExp(
    'create\\s+or\\s+replace\\s+view\\s+public\\.$view'
    '[\\s\\S]*?from\\s+public\\.[a-z_]+'
    '[\\s\\S]*?;',
    caseSensitive: false,
  ).firstMatch(sql);

  expect(match, isNotNull, reason: 'Missing public view $view.');
  return match!.group(0)!;
}

String _columnGrant(String sql, String table) {
  final match = RegExp(
    'grant\\s+select\\s*\\(([\\s\\S]*?)\\)'
    '\\s*on\\s+table\\s+public\\.$table'
    '\\s*to\\s+anon\\s*,\\s*authenticated\\s*;',
    caseSensitive: false,
  ).firstMatch(sql);

  expect(match, isNotNull, reason: 'Missing restricted grant for $table.');
  return match!.group(1)!.toLowerCase();
}
