import 'package:fishtrack/core/map/map_entity_focus.dart';
import 'package:fishtrack/core/map/pending_map_camera.dart';
import 'package:flutter_test/flutter_test.dart';

RuntimeMapCameraTarget _target({
  required String source,
  required String entityId,
}) => RuntimeMapCameraTarget(
  source: source,
  entityId: entityId,
  latitude: 44.16,
  longitude: 24.48,
  zoom: 8,
);

void main() {
  group('MapEntityFocusCoordinator', () {
    test('canonical entity focus is consumed exactly once', () {
      final coordinator = MapEntityFocusCoordinator();
      coordinator.arm(
        _target(source: 'hydro-notification', entityId: 'plant-draganesti'),
      );

      expect(coordinator.pendingEntityId, 'plant-draganesti');
      expect(coordinator.consume('plant-draganesti'), isTrue);
      expect(coordinator.pendingEntityId, isNull);
      expect(coordinator.consume('plant-draganesti'), isFalse);
    });

    test('manual selection can cancel stale entity focus', () {
      final coordinator = MapEntityFocusCoordinator();
      coordinator.arm(
        _target(source: 'hydro-notification', entityId: 'plant-draganesti'),
      );
      coordinator.cancel();

      expect(coordinator.pendingEntityId, isNull);
    });

    test('browse and device camera targets never become entity focus', () {
      final coordinator = MapEntityFocusCoordinator();

      coordinator.arm(
        _target(source: 'hydro-dispatch-selector', entityId: 'country-pack-ro'),
      );
      expect(coordinator.pendingEntityId, isNull);

      coordinator.arm(
        _target(source: 'device-location', entityId: 'device-location'),
      );
      expect(coordinator.pendingEntityId, isNull);
    });
  });
}
