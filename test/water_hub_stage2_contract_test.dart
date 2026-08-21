import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Water Hub exposes canonical intelligent selector contract', () {
    final source = File(
      'lib/features/figma_complete/presentation/figma_environment_pages.dart',
    ).readAsStringSync();
    for (final label in <String>[
      'Automat',
      'Dunăre',
      'Râuri',
      'Baraje hidro',
      'Favorite',
    ]) {
      expect(source, contains("'$label'"));
    }
    expect(source, contains('getHubRivers()'));
    expect(source, contains('getHubHydropowerComplexes()'));
    expect(source, contains('SelectedContext.fromRiver'));
    expect(source, contains('SelectedContext.fromHydropowerComplex'));
  });

  test('Home Water card promotes station identity', () {
    final source = File(
      'lib/features/commercial_home/presentation/commercial_home_page.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('final stationName = snapshot?.station?.name.trim();'),
    );
    expect(source, contains('return stationName;'));
  });
}
