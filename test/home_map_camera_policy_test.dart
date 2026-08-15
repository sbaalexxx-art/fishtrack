import 'dart:io';

import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/widgets/home_premium/home_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const bristol = LatLng(51.4545, -2.5879);
  const cachedBristol = LatLng(51.4500, -2.5800);
  const romaniaSearch = LatLng(44.8167, 21.3944);

  CurrentLocationState physicalState(
    CurrentLocationStatus status,
    LatLng location,
  ) => CurrentLocationState(
    status: status,
    location: CurrentDeviceLocation(
      latitude: location.latitude,
      longitude: location.longitude,
      accuracyMeters: 8,
      observedAt: DateTime.now(),
    ),
  );

  test('no usable physical location keeps Mapbox behind loading surface', () {
    expect(homeMapDeviceCenter(const CurrentLocationState()), isNull);
    expect(
      selectInitialHomeMapPhysicalCamera(
        current: null,
        canonical: const CurrentLocationState(),
      ),
      isNull,
    );
    expect(
      homeMapDeviceCenter(
        physicalState(CurrentLocationStatus.locating, romaniaSearch),
      ),
      isNull,
    );

    final ownerSource = File(
      'lib/widgets/home_premium/home_map.dart',
    ).readAsStringSync();
    expect(ownerSource, contains('home-map-location-loading'));
    expect(ownerSource, contains('if (initialPhysicalCamera == null)'));
    expect(
      ownerSource.indexOf('if (initialPhysicalCamera == null)'),
      lessThan(ownerSource.indexOf('final map = HomeMap(')),
    );
  });

  test('valid cached physical location is the first Mapbox camera', () {
    final cached = physicalState(CurrentLocationStatus.cached, cachedBristol);
    expect(homeMapDeviceCenter(cached), cachedBristol);
    expect(
      selectInitialHomeMapPhysicalCamera(current: null, canonical: cached),
      cachedBristol,
    );

    final rendererSource = File(
      'lib/widgets/home/home_map_renderer.dart',
    ).readAsStringSync();
    expect(rendererSource, contains('required this.initialCamera'));
    expect(rendererSource, contains('viewport: mapbox.CameraViewportState('));
    expect(rendererSource, contains('widget.initialCamera.longitude'));
    expect(rendererSource, contains('widget.initialCamera.latitude'));
  });

  test('later current GPS can refine the cached startup camera', () {
    final available = physicalState(CurrentLocationStatus.available, bristol);
    expect(
      selectInitialHomeMapPhysicalCamera(
        current: cachedBristol,
        canonical: available,
      ),
      cachedBristol,
    );
    expect(
      shouldApplyAutomaticHomeMapCamera(
        explorationCenter: null,
        didApplyInitialPhysicalCamera: true,
        appliedPhysicalCameraWasCached: true,
        resolvedStatus: CurrentLocationStatus.available,
      ),
      isTrue,
    );
  });

  test('Home startup camera has no hardcoded geographic fallback', () {
    final ownerSource = File(
      'lib/widgets/home_premium/home_map.dart',
    ).readAsStringSync();
    final rendererSource = File(
      'lib/widgets/home/home_map_renderer.dart',
    ).readAsStringSync();

    for (final forbidden in <String>[
      '44.8167',
      '21.3944',
      '51.4545',
      '-2.5879',
      'initialCenter ??',
      'viewport: null',
    ]) {
      expect('$ownerSource\n$rendererSource', isNot(contains(forbidden)));
    }
  });

  test('selected context cannot become the Home startup camera', () {
    final ownerSource = File(
      'lib/widgets/home_premium/home_map.dart',
    ).readAsStringSync();

    expect(ownerSource, contains('ref.watch(currentLocationProvider)'));
    expect(ownerSource, isNot(contains('selectedContextProvider')));
    expect(ownerSource, isNot(contains('SelectedContext')));
  });

  test('Home renderer has no independent camera or fallback authority', () {
    final source = File(
      'lib/widgets/home/home_map_renderer.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_initialViewport')));
    expect(source, isNot(contains('_didApplyLocationCamera')));
    expect(source, isNot(contains('_setCamera')));
    expect(source, isNot(contains('.setCamera(')));
    expect(source, isNot(contains('44.8148')));
    expect(source, isNot(contains('21.3895')));
    expect(source, isNot(contains('water_station')));
    expect(source, isNot(contains('_stationAnnotationManager')));
    expect(source, contains('_locationContextAnnotationManager'));
    expect(source, contains('_reportAnnotationManager'));
  });

  test('cached camera can yield to the later available physical GPS fix', () {
    expect(
      shouldApplyAutomaticHomeMapCamera(
        explorationCenter: null,
        didApplyInitialPhysicalCamera: false,
        appliedPhysicalCameraWasCached: false,
        resolvedStatus: CurrentLocationStatus.cached,
      ),
      isTrue,
    );
    expect(
      shouldApplyAutomaticHomeMapCamera(
        explorationCenter: null,
        didApplyInitialPhysicalCamera: true,
        appliedPhysicalCameraWasCached: true,
        resolvedStatus: CurrentLocationStatus.available,
      ),
      isTrue,
    );
    expect(
      shouldApplyAutomaticHomeMapCamera(
        explorationCenter: null,
        didApplyInitialPhysicalCamera: true,
        appliedPhysicalCameraWasCached: false,
        resolvedStatus: CurrentLocationStatus.available,
      ),
      isFalse,
    );
  });

  test('explicit exploration cannot be replaced by automatic GPS', () {
    const exploration = HomeMapCameraRequest(
      target: romaniaSearch,
      zoom: 13.5,
      intent: HomeMapCameraIntent.exploration,
    );
    const automaticGps = HomeMapCameraRequest(
      target: bristol,
      zoom: 12.5,
      intent: HomeMapCameraIntent.automaticLocation,
    );

    final selected = selectPendingHomeMapCameraRequest(
      current: exploration,
      incoming: automaticGps,
    );

    expect(identical(selected, exploration), isTrue);
    expect(
      shouldApplyAutomaticHomeMapCamera(
        explorationCenter: romaniaSearch,
        didApplyInitialPhysicalCamera: false,
        appliedPhysicalCameraWasCached: false,
        resolvedStatus: CurrentLocationStatus.available,
      ),
      isFalse,
    );
  });

  test('Locate clears exploration and overrides its pending camera', () {
    const exploration = HomeMapCameraRequest(
      target: romaniaSearch,
      zoom: 13.5,
      intent: HomeMapCameraIntent.exploration,
    );
    const locate = HomeMapCameraRequest(
      target: bristol,
      zoom: 13.5,
      intent: HomeMapCameraIntent.locate,
    );

    final selected = selectPendingHomeMapCameraRequest(
      current: exploration,
      incoming: locate,
    );

    expect(identical(selected, locate), isTrue);
    expect(
      homeMapExplorationCenterAfterIntent(
        current: romaniaSearch,
        intent: HomeMapCameraIntent.locate,
      ),
      isNull,
    );
  });

  test('Search replaces a pending automatic location camera', () {
    const automaticGps = HomeMapCameraRequest(
      target: cachedBristol,
      zoom: 12.5,
      intent: HomeMapCameraIntent.automaticLocation,
    );
    const exploration = HomeMapCameraRequest(
      target: romaniaSearch,
      zoom: 13.5,
      intent: HomeMapCameraIntent.exploration,
    );

    final selected = selectPendingHomeMapCameraRequest(
      current: automaticGps,
      incoming: exploration,
    );

    expect(identical(selected, exploration), isTrue);
    expect(
      homeMapExplorationCenterAfterIntent(
        current: null,
        intent: HomeMapCameraIntent.exploration,
        explorationTarget: romaniaSearch,
      ),
      romaniaSearch,
    );
  });
}
