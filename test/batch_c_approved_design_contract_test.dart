import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Batch C approved review surfaces are present without demo values', () {
    final activity = File(
      'lib/features/shell/presentation/activity_hub_page.dart',
    ).readAsStringSync();
    final utilities = File(
      'lib/features/shell/presentation/utilities_hub_page.dart',
    ).readAsStringSync();
    final community = File(
      'lib/features/figma_complete/presentation/figma_community_pages.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/figma_complete/presentation/figma_account_pages.dart',
    ).readAsStringSync();
    final environment = File(
      'lib/features/figma_complete/presentation/figma_environment_pages.dart',
    ).readAsStringSync();

    expect(activity, contains("ValueKey('activity-hub-page')"));
    expect(activity, contains('Notificări și istoricul tău de pescuit'));
    expect(activity, contains('REZUMAT PERSONAL'));

    expect(utilities, contains("ValueKey('utilities-hub-page')"));
    expect(utilities, contains('FluviExploreCatalog.grouped'));
    expect(utilities, contains("ValueKey('utilities-section-\$sectionKey')"));
    expect(
      utilities,
      contains("ValueKey('utilities-section-toggle-\$sectionKey')"),
    );
    expect(utilities, contains("ValueKey('utilities-search-field')"));
    expect(utilities, isNot(contains('GridView')));

    expect(community, contains("ValueKey('figma-community-page')"));
    expect(community, contains("ValueKey('figma-add-catch')"));
    expect(community, contains("ValueKey('figma-reports-archive')"));
    expect(community, contains('SPECIE · CONFIRMARE NECESARĂ'));
    expect(community, contains('TEMPORARE · CONFIRMATE · CU LOCAȚIE'));

    expect(settings, contains("ValueKey('figma-settings-page')"));
    expect(settings, contains('Setări aplicație & ajutor'));
    expect(settings, contains("ValueKey('settings-theme-selector')"));

    expect(environment, contains('SingleChildScrollView('));
    expect(environment, contains("(_WaterHubCategory.rivers, 'Râuri')"));

    expect(activity, isNot(contains('6 sesiuni · 14 capturi · 3 rapoarte')));
    expect(community, isNot(contains('Clean 72%')));
    expect(community, isNot(contains('ÎNCREDERE 82')));
    expect(community, isNot(contains('CIORNĂ LOCALĂ')));
  });
}
