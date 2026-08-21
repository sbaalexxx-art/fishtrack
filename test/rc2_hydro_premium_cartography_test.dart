import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RC2 Hydro premium cartography contracts', () {
    test('secondary river network is suppressed at national zoom', () {
      final overlay = File(
        'lib/core/map/hydro_ro_vector_overlay.dart',
      ).readAsStringSync();

      expect(overlay, contains('minZoom: 7.4'));
      expect(overlay, contains('minZoom: 4.75'));
      expect(overlay, contains('minZoom: 4.0'));
    });

    test(
      'community reports and catches use semantic premium point markers',
      () {
        final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

        expect(
          mapPage,
          contains('mapbox.PointAnnotationManager? _reportAnnotationManager;'),
        );
        expect(
          mapPage,
          contains('mapbox.PointAnnotationManager? _catchAnnotationManager;'),
        );
        expect(mapPage, contains(r'fluviai-report-${category.name}-v3'));
        expect(mapPage, contains("const imageId = 'fluviai-catch-v3';"));
        expect(mapPage, contains('FluviMapPinSystem.rasterize('));
        expect(mapPage, contains("'severity': critical"));
        expect(
          mapPage,
          isNot(
            contains('void _handleReportAnnotationTap(mapbox.CircleAnnotation'),
          ),
        );
      },
    );

    test('critical report families remain red and warning stays amber', () {
      final registry = File(
        'lib/core/map/map_feature_registry.dart',
      ).readAsStringSync();

      expect(registry, contains('danger = Color(0xFFFF4D5A)'));
      expect(registry, contains('theft = Color(0xFFE53945)'));
      expect(registry, contains('obstacle = Color(0xFFFF9F43)'));
      expect(registry, contains('ReportCategory.poaching => danger'));
      expect(registry, contains('ReportCategory.theftWarning => theft'));
    });

    test('pin renderer retains shape plus icon plus color semantics', () {
      final renderer = File(
        'lib/core/map/fluviai_map_pin_system.dart',
      ).readAsStringSync();

      expect(renderer, contains('case MapMarkerShape.dam:'));
      expect(renderer, contains('case MapMarkerShape.hydropower:'));
      expect(renderer, contains('case MapMarkerShape.warning:'));
      expect(renderer, contains('case MapMarkerShape.shield:'));
      expect(renderer, contains('math.pi * 1.08'));
    });
  });
}
