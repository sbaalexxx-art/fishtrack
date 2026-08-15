import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('Mapbox runtime and approved Full Map controls remain connected', () {
    final map = source('lib/screens/map_page.dart');

    expect(map, contains('MapboxMapView('));
    expect(map, contains("ValueKey('aifishmap-map-page-mapbox')"));

    expect(map, contains("ValueKey('figma-full-map-search')"));
    expect(map, contains("ValueKey('figma-full-map-layers')"));
    expect(map, contains("ValueKey('figma-full-map-boat-hud')"));
    expect(map, contains("ValueKey('figma-full-map-locate')"));
    expect(map, contains("ValueKey('figma-full-map-quick-report')"));
    expect(map, contains('Întreabă Fluvi'));

    expect(map, contains("ValueKey('full-map-pin-preview')"));
    expect(map, contains("ValueKey('full-map-approved-filters')"));
    expect(map, contains("ValueKey('full-map-filter-stations')"));
    expect(map, contains("ValueKey('full-map-filter-reports')"));
    expect(map, contains("ValueKey('full-map-filter-favorites')"));
    expect(map, contains("ValueKey('full-map-filter-radius')"));
    expect(map, contains("ValueKey('full-map-filter-apply')"));

    expect(map, contains('filterFullMapReports('));
    expect(map, contains('filterFullMapStations('));
    expect(map, contains('widget.onCreateReport'));
    expect(map, contains('_toggleFavorite(station)'));
    expect(map, contains('FavoriteStationsService'));

    expect(map, isNot(contains('bottomNavigationBar:')));
  });
  test('water chart follows the approved minimal visual contract', () {
    final water = source('lib/screens/water_level_page.dart');
    expect(water, contains('isCurved: segment.usesBezier'));
    expect(water, contains('belowBarData: BarAreaData('));
    expect(water, contains('gridData: const FlGridData(show: false)'));
    expect(
      water,
      contains('checkToShowDot: (spot, _) => showObservationDot(spot)'),
    );
    expect(water, contains('class _ChartAxisText'));
  });

  test(
    'shell keeps IndexedStack and routes archive without GoRouter migration',
    () {
      final shell = source('lib/screens/main_navigation.dart');
      final router = source(
        'lib/features/figma_complete/presentation/figma_destination_router.dart',
      );
      expect(shell, contains('IndexedStack'));
      expect(shell, contains('AppNavigator.attachShellNavigator'));
      expect(shell, contains('AppNavigator.attachMainTabRouteSelector'));
      expect(
        router,
        contains('AppDestination.myReports => const FigmaReportsArchivePage()'),
      );
      expect(shell, isNot(contains('GoRouter')));
    },
  );

  test('critical truthful fallback surfaces are present', () {
    expect(
      source('lib/screens/add_catch_page.dart'),
      contains("Key('catch-fluvi-vision-quality')"),
    );
    expect(
      source('lib/screens/premium_page.dart'),
      contains('UnavailableBillingRepository'),
    );
    expect(
      source('lib/screens/product_destination_page.dart'),
      contains('AI answers are not connected yet'),
    );
    expect(
      source('lib/screens/alerts_page.dart'),
      contains('AlertRuleRepository'),
    );
  });
}
