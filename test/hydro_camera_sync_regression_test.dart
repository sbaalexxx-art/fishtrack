import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const parentCamera = 'onCameraChange: _handleMapCameraChange';
  const mapboxCamera = 'onCameraChangeListener: widget.onCameraChange';
  const handler = '_handleMapCameraChange(mapbox.CameraChangedEventData data)';
  const oldZoomGate = '_cameraZoom >= 11.4';
  const densityReturn = 'return densityKeys.contains(key);';
  const gold = 'static const Color hydropower = Color(0xFFE8C878);';
  const oldPurple = 'Color(0xFF7C6CFF)';
  const imageV3 = r'fluviai-hydropower-$operation-r$reportBadge-v3';
  const dockGold = 'static const _cyan = Color(0xFFE8C878);';

  final mapPage = File('lib/screens/map_page.dart').readAsStringSync();
  final registry = File(
    'lib/core/map/map_feature_registry.dart',
  ).readAsStringSync();
  final dock = File(
    'lib/features/hydro_dispatch/presentation/hydro_dispatch_functional_dock.dart',
  ).readAsStringSync();

  group('Hydro camera sync', () {
    test('camera updates presentation without network churn', () {
      expect(mapPage, contains(parentCamera));
      expect(mapPage, contains(mapboxCamera));
      expect(mapPage, contains(handler));
      expect(mapPage, contains('_hydroCameraPresentationBucket(_cameraZoom)'));
      expect(mapPage, contains('_hydroCameraPresentationBucket(zoom)'));
      expect(mapPage, contains('Network/data refresh stays on'));
      expect(mapPage, contains('await _refreshWaterAssetsAtCamera();'));
    });

    test('legacy Hydro zoom gate is absent', () {
      final start = mapPage.indexOf(
        'List<WaterMapPin> get _visibleHydropowerPins',
      );
      final end = mapPage.indexOf('Color _hydropowerOperationColor', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final visibility = mapPage.substring(start, end);
      expect(visibility, contains(densityReturn));
      expect(visibility, isNot(contains(oldZoomGate)));
    });

    test('Hydro identity is Gold with refreshed marker cache', () {
      expect(registry, contains(gold));
      expect(registry, isNot(contains(oldPurple)));
      expect(mapPage, contains(imageV3));
      expect(mapPage, contains('final haloColor = selected'));
      expect(mapPage, contains('MapFeatureRegistry.hydropower'));
    });

    test('Today and Tomorrow are vertically ordered', () {
      expect(dock, contains(dockGold));
      final today = dock.indexOf('data: today');
      final spacer = dock.indexOf('const SizedBox(height: 10)', today);
      final tomorrow = dock.indexOf('data: tomorrow', spacer);
      expect(today, greaterThanOrEqualTo(0));
      expect(spacer, greaterThan(today));
      expect(tomorrow, greaterThan(spacer));
    });
  });
}
