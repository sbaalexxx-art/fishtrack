import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260728120000_import_romania_water_catalog.sql';

void main() {
  late String sql;

  setUpAll(() async {
    sql = await File(_migrationPath).readAsString();
  });

  test('records the exact approved W4B artifacts', () {
    expect(sql, contains('dams rows: 2202'));
    expect(
      sql,
      contains(
        '65BD92CE64DC3DF211C948C8CA6EE780EE31E3349BEA9E6AC1443CD483344BB7',
      ),
    );
    expect(sql, contains('reservoirs rows: 1933'));
    expect(
      sql,
      contains(
        '1F75123AB88442CB2393F1B52F1BBBDE559043216DECBB48148F0CAED6A3F2E1',
      ),
    );
    expect(sql, contains('eligible relations rows: 1090'));
    expect(
      sql,
      contains(
        'E907821A48FF67C598ADC29599438923A8B180A05341188C2395E05180BEF63B',
      ),
    );
  });

  test('wraps the complete import in one transaction', () {
    expect(sql.trimLeft().toLowerCase(), contains('begin;'));
    expect(sql.trimRight().toLowerCase().endsWith('commit;'), isTrue);
  });

  test('embeds only the three eligible canonical source sets', () {
    expect(sql, contains(r'$w4d3_dams$'));
    expect(sql, contains(r'$w4d3_reservoirs$'));
    expect(sql, contains(r'$w4d3_relations$'));
    expect(sql, contains('jsonb_to_recordset'));
    expect(sql, contains('W4D-3 dam source row count mismatch.'));
    expect(sql, contains('W4D-3 reservoir source row count mismatch.'));
    expect(sql, contains('W4D-3 relation source row count mismatch.'));
    expect(sql, isNot(contains('water-premium-w4b-review-relations.csv')));
    expect(sql, isNot(contains('water-premium-w4b-rejected-entities.csv')));
  });

  test('rejects duplicate source identities before writing', () {
    expect(sql, contains('W4D-3 duplicate dam source identity.'));
    expect(sql, contains('W4D-3 duplicate reservoir source identity.'));
    expect(sql, contains('W4D-3 duplicate eligible relation identity.'));
  });

  test('converts raw payloads and evidence into jsonb objects', () {
    expect(sql, contains('raw_payload_json::jsonb'));
    expect(sql, contains('relation_source.evidence_json::jsonb'));
    expect(sql, contains("jsonb_typeof(raw_payload_json::jsonb) <> 'object'"));
    expect(sql, contains("jsonb_typeof(evidence_json::jsonb) <> 'object'"));
  });

  test('upserts dams and reservoirs by canonical source identity', () {
    expect(
      RegExp(
        r'insert\s+into\s+public\.dams\s+as\s+target[\s\S]*?'
        r'on\s+conflict\s*\(\s*source\s*,\s*country_code\s*,'
        r'\s*source_asset_id\s*\)',
        caseSensitive: false,
      ).hasMatch(sql),
      isTrue,
    );
    expect(
      RegExp(
        r'insert\s+into\s+public\.reservoirs\s+as\s+target[\s\S]*?'
        r'on\s+conflict\s*\(\s*source\s*,\s*country_code\s*,'
        r'\s*source_asset_id\s*\)',
        caseSensitive: false,
      ).hasMatch(sql),
      isTrue,
    );
  });

  test('does not overwrite later canonical water-body links', () {
    final insertSections = RegExp(
      r'insert\s+into\s+public\.(?:dams|reservoirs)\s+as\s+target'
      r'([\s\S]*?)on\s+conflict',
      caseSensitive: false,
    ).allMatches(sql);

    expect(insertSections, hasLength(2));
    for (final section in insertSections) {
      expect(section.group(1), isNot(contains('water_body_id')));
    }

    expect(
      sql,
      contains("- array['id', 'created_at', 'updated_at', 'water_body_id']"),
    );
  });

  test('preserves nullable values and ANAR use codes', () {
    for (final field in <String>[
      'surface_area_km2',
      'perimeter_km',
      'volume_million_m3',
      'flood_attenuation_volume_million_m3',
      'dam_height_m',
      'mean_depth_m',
      'elevation_m',
      'risk_index',
    ]) {
      expect(
        sql,
        contains("nullif(btrim($field), '')"),
        reason: '$field must accept an empty source value as NULL.',
      );
    }

    expect(sql, contains("nullif(btrim(relation_source.distance_km), '')"));

    for (final field in <String>[
      'hydropower_use',
      'fishery_use',
      'water_supply_use',
      'recreation_use',
    ]) {
      expect(sql, contains("nullif(btrim($field), '')"));
    }

    expect(sql, contains("hydropower_use not in ('H')"));
    expect(sql, contains("upper(fishery_use) not in ('P')"));
    expect(sql, contains('W4D-3 expected 1310 uppercase P fishery codes.'));
    expect(sql, contains('W4D-3 expected 4 lowercase p fishery codes.'));
    expect(sql, contains("water_supply_use not in ('A')"));
    expect(sql, contains("recreation_use not in ('R')"));
  });

  test('resolves relation source ids to canonical UUID foreign keys', () {
    expect(RegExp(r"on\s+dam\.source = 'ANAR'").allMatches(sql).length, 3);
    expect(
      RegExp(r"on\s+reservoir\.source = 'ANAR'").allMatches(sql).length,
      3,
    );
    expect(
      sql,
      contains(
        'dam.source_asset_id = btrim(relation_source.dam_source_asset_id)',
      ),
    );
    expect(
      sql,
      contains(
        'reservoir.source_asset_id =\n'
        '      btrim(relation_source.reservoir_source_asset_id)',
      ),
    );
    expect(sql, contains('W4D-3 has % unresolved eligible relations.'));
    expect(
      sql,
      contains('W4D-3 resolves to % duplicate canonical relation pairs.'),
    );
  });

  test('upserts only the eligible canonical relation pairs', () {
    expect(
      RegExp(
        r'insert\s+into\s+public\.dam_reservoir_relations\s+as\s+target'
        r'[\s\S]*?on\s+conflict\s*\(\s*relation_type\s*,\s*dam_id\s*,'
        r'\s*reservoir_id\s*\)',
        caseSensitive: false,
      ).hasMatch(sql),
      isTrue,
    );
    expect(sql, contains('confidence = excluded.confidence'));
    expect(sql, contains('distance_km = excluded.distance_km'));
    expect(sql, contains('evidence = excluded.evidence'));
  });

  test('uses state-idempotent updates', () {
    expect(
      RegExp(
        r'to_jsonb\(target\)[\s\S]*?is\s+distinct\s+from'
        r'[\s\S]*?to_jsonb\(excluded\)',
        caseSensitive: false,
      ).allMatches(sql).length,
      3,
    );
  });

  test('preserves stations and snapshots exactly', () {
    expect(sql, contains('W4D-3 changed public.stations.'));
    expect(sql, contains('W4D-3 changed public.daily_water_snapshots.'));
    expect(sql, contains('W4D-3 changed snapshot station identity.'));

    for (final table in <String>['stations', 'daily_water_snapshots']) {
      expect(
        RegExp(
          '(?:insert\\s+into|update|delete\\s+from|truncate(?:\\s+table)?)'
          '\\s+public\\.$table',
          caseSensitive: false,
        ).hasMatch(sql),
        isFalse,
        reason: 'W4D-3 must not write public.$table.',
      );
    }
  });

  test('never deletes or truncates canonical catalog data', () {
    expect(
      RegExp(
        r'delete\s+from\s+public\.(?:dams|reservoirs|'
        r'dam_reservoir_relations)',
        caseSensitive: false,
      ).hasMatch(sql),
      isFalse,
    );
    expect(
      RegExp(
        r'truncate(?:\s+table)?\s+public\.(?:dams|reservoirs|'
        r'dam_reservoir_relations)',
        caseSensitive: false,
      ).hasMatch(sql),
      isFalse,
    );
  });

  test('enforces exact imported and public catalog counts', () {
    expect(sql, contains('W4D-3 expected 2202 imported dams'));
    expect(sql, contains('W4D-3 expected 1933 imported reservoirs'));
    expect(sql, contains('W4D-3 expected 1090 imported relations'));
    expect(sql, contains('W4D-3 expected 926 audit-qualified relations.'));
    expect(sql, contains('W4D-3 expected 164 ANAR-provenance relations.'));
    expect(sql, contains('W4D-3 expected 2200 map-eligible public dams'));
    expect(sql, contains('W4D-3 expected 1933 map-eligible public reservoirs'));
    expect(sql, contains('W4D-3 expected 1090 public relations'));
  });

  test('requires the canonical Romania water identity foundation', () {
    expect(sql, contains("canonical_key = 'ro-danube'"));
    expect(
      sql,
      contains(
        'W4D-3 requires the canonical Romania water identity migration.',
      ),
    );
  });
}
