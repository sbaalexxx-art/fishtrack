import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hydro camera synchronization contract', () {
    final mapPage = File('lib/screens/map_page.dart').readAsStringSync();
    final registry = File(
      'lib/core/map/map_feature_registry.dart',
    ).readAsStringSync();
    final dock = File(
      'lib/features/hydro_dispatch/presentation/hydro_dispatch_functional_dock.dart',
    ).readAsStringSync();

    test(
      'updates Hydro presentation in both zoom directions without network churn',
      () {
        expect(mapPage, contains('onCameraChange: _handleMapCameraChange'));
        expect(
          mapPage,
          contains('onCameraChangeListener: widget.onCameraChange'),
        );
        expect(
          mapPage,
          contains('_handleMapCameraChange(mapbox.CameraChangedEventData data)'),
        );
        expect(
          mapPage,
          contains('_hydroCameraPresentationBucket(_cameraZoom)'),
        );
        expect(mapPage, contains('_hydroCameraPresentationBucket(zoom)'));
        expect(mapPage, contains('Network/data refresh stays on'));
        expect(mapPage, contains('await _refreshWaterAssetsAtCamera();'));
      },
    );

    test('does not retain the legacy 11.4 Hydro visibility gate', () {
      final start = mapPage.indexOf(
        'List<WaterMapPin> get _visibleHydropowerPins',
      );
      final end = mapPage.indexOf(
        'Color _hydropowerOperationColor',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final visibility = mapPage.substring(start, end);
      expect(visibility, contains('return densityKeys.contains(key);'));
      expect(visibility, isNot(contains('_cameraZoom >= 11.4')));
    });

    test('uses durable Gold Hydro identity and invalidated marker cache', () {
      expect(
        registry,
        contains('static const Color hydropower = Color(0xFFE8C878);'),
      );
      expect(registry, isNot(contains('Color(0xFF7C6CFF)')));
      expect(
        mapPage,
        contains(r'fluviai-hydropower-$operation-r$reportBadge-v3'),
      );
      expect(
        mapPage,
        contains(
          'final haloColor = selected\n          ? MapFeatureRegistry.hydropower\n          : operationColor;',
        ),
      );
    });

    test('keeps Today and Tomorrow vertically stacked in Hydro PRO', () {
      expect(dock, contains('static const _cyan = Color(0xFFE8C878);'));
      final today = dock.indexOf('data: today');
      final spacer = dock.indexOf('const SizedBox(height: 10)', today);
      final tomorrow = dock.indexOf('data: tomorrow', spacer);
      expect(today, greaterThanOrEqualTo(0));
      expect(spacer, greaterThan(today));
      expect(tomorrow, greaterThan(spacer));
    });
  });
}
