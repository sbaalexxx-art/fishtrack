import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Water Stage 2.1 keeps context and functional navigation together', () {
    final source = File(
      'lib/features/figma_complete/presentation/figma_environment_pages.dart',
    ).readAsStringSync();

    for (final label in <String>[
      'Automat',
      'DunÄƒre',
      'RÃ¢uri',
      'Baraje hidro',
      'Favorite',
      'Rezumat',
      'TendinÈ›Äƒ',
      'StaÈ›ii',
      'Alerte',
    ]) {
      expect(source, contains("'$label'"));
    }
    expect(source, contains('class _WaterContextBar'));
    expect(source, contains('class _WaterSegmentBar'));
  });

  test(
    'Home Water card exposes dynamic station identity in compact layout',
    () {
      final source = File(
        'lib/features/commercial_home/presentation/commercial_home_page.dart',
      ).readAsStringSync();
      expect(source, contains("ValueKey('home-water-station-name')"));
      expect(
        source,
        contains('final stationName = snapshot?.station?.name.trim'),
      );
      expect(source, contains("ValueKey('home-water-station-name')"));
    },
  );
}
