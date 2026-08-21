import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String scoped(String text, String start, String end) {
  final a = text.indexOf(start);
  final b = text.indexOf(end, a + start.length);
  expect(a, greaterThanOrEqualTo(0), reason: 'Missing scope start: $start');
  expect(b, greaterThan(a), reason: 'Missing scope end: $end');
  return text.substring(a, b);
}

void main() {
  group('RC2.2C FINAL Hydro cartographic language', () {
    test('entity type is carried by a unique silhouette', () {
      final registry = File(
        'lib/core/map/map_feature_registry.dart',
      ).readAsStringSync();
      final renderer = File(
        'lib/core/map/fluviai_map_pin_system.dart',
      ).readAsStringSync();

      final river = scoped(
        registry,
        'MapFeatureType.river => MapFeaturePresentation(',
        'MapFeatureType.branch =>',
      );
      final reservoir = scoped(
        registry,
        'MapFeatureType.reservoir => MapFeaturePresentation(',
        'MapFeatureType.hydropower =>',
      );
      final dam = scoped(
        registry,
        'MapFeatureType.dam => MapFeaturePresentation(',
        'MapFeatureType.reservoir =>',
      );
      final hydro = scoped(
        registry,
        'MapFeatureType.hydropower => MapFeaturePresentation(',
        'MapFeatureType.fishingPlace =>',
      );
      final station = scoped(
        registry,
        'MapFeatureType.monitoringStation => MapFeaturePresentation(',
        'MapFeatureType.river =>',
      );

      expect(river, contains('markerShape: MapMarkerShape.river'));
      expect(reservoir, contains('markerShape: MapMarkerShape.reservoir'));
      expect(dam, contains('markerShape: MapMarkerShape.dam'));
      expect(hydro, contains('markerShape: MapMarkerShape.hydropower'));
      expect(station, contains('markerShape: MapMarkerShape.pin'));

      expect(renderer, contains('case MapMarkerShape.river:'));
      expect(renderer, contains('case MapMarkerShape.reservoir:'));
      expect(renderer, contains('case MapMarkerShape.dam:'));
      expect(renderer, contains('case MapMarkerShape.hydropower:'));
    });

    test(
      'geometry remains primary and Hydro uses semantic density across zoom',
      () {
        final mapPage = File('lib/screens/map_page.dart').readAsStringSync();
        final overlay = File(
          'lib/core/map/hydro_ro_vector_overlay.dart',
        ).readAsStringSync();

        expect(overlay, isNot(contains("textField: '\u25C6'")));
        expect(
          overlay,
          contains(
            'symbols are rendered only from canonical runtime WaterAsset annotations',
          ),
        );

        final waterVisibility = scoped(
          mapPage,
          'List<WaterAssetRef> get _visibleWaterAssets',
          'Set<String> get _visibleHydroDensityKeys',
        );
        expect(waterVisibility, contains('localCanonicalReservoir'));
        expect(
          waterVisibility,
          contains(
            'asset.type == WaterAssetType.reservoir && _cameraZoom >= 10.2',
          ),
        );
        expect(
          waterVisibility,
          contains('asset.type == WaterAssetType.dam && _cameraZoom >= 11.6'),
        );

        final hydroVisibility = scoped(
          mapPage,
          'List<WaterMapPin> get _visibleHydropowerPins',
          'Color _hydropowerOperationColor',
        );
        expect(hydroVisibility, contains('return densityKeys.contains(key);'));
        expect(hydroVisibility, isNot(contains('_cameraZoom >= 11.4')));
        expect(hydroVisibility, isNot(contains('plant.priority >= 80')));
      },
    );

    test('CHE identity is Gold and distinct from operation state', () {
      final registry = File(
        'lib/core/map/map_feature_registry.dart',
      ).readAsStringSync();
      final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

      expect(
        registry,
        contains('static const Color hydropower = Color(0xFFE8C878);'),
      );
      expect(registry, isNot(contains('Color(0xFF7C6CFF)')));

      final sync = scoped(
        mapPage,
        'Future<void> _syncHydropowerAnnotations()',
        'Future<String?> _ensureHydropowerStyleImage',
      );
      expect(
        sync,
        isNot(
          contains(
            '.copyWith(color: _hydropowerOperationColor(pin.operationState))',
          ),
        ),
      );
      expect(
        sync,
        contains('_hydropowerOperationColor(pin.operationState)'),
        reason: 'Operation state must remain as halo/accent.',
      );
      expect(sync, contains('MapFeatureRegistry.hydropower'));
      expect(sync, contains('iconAnchor: mapbox.IconAnchor.CENTER'));
    });

    test('Full Map Ask Fluvi matches the compact Home control language', () {
      final mapPage = File('lib/screens/map_page.dart').readAsStringSync();
      expect(mapPage, contains('controlSize: const Size(48, 48)'));
      expect(mapPage, contains('Icons.auto_awesome_rounded'));
      expect(mapPage, isNot(contains('controlSize: const Size(140, 48)')));
      expect(mapPage, contains('AppDestination.askFluvi'));
    });

    test('1C Danube persistence and 1D2 hierarchy stay protected', () {
      final mapPage = File('lib/screens/map_page.dart').readAsStringSync();
      final pages = File(
        'lib/features/figma_complete/presentation/figma_environment_pages.dart',
      ).readAsStringSync();

      final overlay = File(
        'lib/core/map/hydro_ro_vector_overlay.dart',
      ).readAsStringSync();
      expect(overlay, contains("'dunare'"));
      expect(
        mapPage,
        contains('HydroRoMapboxOverlay.isDanubeName(station.river)'),
      );
      expect(
        pages,
        contains('final hasCurrentData = _hasCurrentWaterData(data);'),
      );
      expect(pages, contains('Widget _currentDataUnavailable()'));
    });
  });
}
