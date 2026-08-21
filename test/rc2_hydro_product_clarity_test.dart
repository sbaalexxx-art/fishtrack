import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RC2.2C-1D2 Hydro product clarity source contracts', () {
    test(
      'dam and hydropower markers are visually distinct and semantically gated',
      () {
        final registry = File(
          'lib/core/map/map_feature_registry.dart',
        ).readAsStringSync();
        final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

        expect(
          registry,
          contains('static const Color dam = Color(0xFF8FA7B3);'),
        );
        expect(
          registry,
          contains('static const Color hydropower = Color(0xFFE8C878);'),
        );

        final damStart = registry.indexOf(
          'MapFeatureType.dam => MapFeaturePresentation(',
        );
        final reservoirStart = registry.indexOf(
          'MapFeatureType.reservoir =>',
          damStart,
        );
        expect(damStart, greaterThanOrEqualTo(0));
        expect(reservoirStart, greaterThan(damStart));
        final damBlock = registry.substring(damStart, reservoirStart);
        expect(damBlock, contains('markerShape: MapMarkerShape.dam'));

        expect(
          mapPage,
          contains('asset.type == WaterAssetType.dam && _cameraZoom >= 11.6'),
        );

        final hydroStart = mapPage.indexOf(
          'List<WaterMapPin> get _visibleHydropowerPins',
        );
        final hydroEnd = mapPage.indexOf(
          'Color _hydropowerOperationColor',
          hydroStart,
        );
        expect(hydroStart, greaterThanOrEqualTo(0));
        expect(hydroEnd, greaterThan(hydroStart));
        final hydroVisibility = mapPage.substring(hydroStart, hydroEnd);
        expect(hydroVisibility, contains('return densityKeys.contains(key);'));
        expect(hydroVisibility, isNot(contains('_cameraZoom >= 11.4')));
        expect(hydroVisibility, isNot(contains('plant.priority >= 80')));

        expect(
          mapPage,
          contains('_hydropowerOperationColor(pin.operationState)'),
        );
        expect(mapPage, contains('onCameraChange: _handleMapCameraChange'));
      },
    );

    test(
      'known catalog facts and relationships precede unavailable current state',
      () {
        final pages = File(
          'lib/features/figma_complete/presentation/figma_environment_pages.dart',
        ).readAsStringSync();

        expect(
          pages,
          contains('final hasCurrentData = _hasCurrentWaterData(data);'),
        );
        expect(pages, contains('Widget _currentDataUnavailable()'));

        final buildStart = pages.indexOf(
          'final hasCurrentData = _hasCurrentWaterData(data);',
        );
        final catalog = pages.indexOf('_catalogData(data.detail)', buildStart);
        final linked = pages.indexOf('_linkedAssets(data.detail)', buildStart);
        final unavailable = pages.indexOf(
          '_currentDataUnavailable()',
          buildStart,
        );

        expect(buildStart, greaterThanOrEqualTo(0));
        expect(catalog, greaterThan(buildStart));
        expect(linked, greaterThan(catalog));
        expect(unavailable, greaterThan(linked));

        expect(
          pages,
          contains(
            'Datele descriptive ANAR rămân disponibile mai sus; FluviAI nu inventează valori curente.',
          ),
        );
      },
    );
  });
}
