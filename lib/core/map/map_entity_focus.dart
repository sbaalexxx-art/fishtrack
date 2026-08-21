import 'pending_map_camera.dart';

/// Keeps entity selection one-shot while camera replay remains persistent.
///
/// [PendingMapCameraCoordinator] intentionally retains the last camera target
/// across style reloads and map re-entry. Entity selection must not share that
/// lifetime: an old CHE must never reassert itself after a later user tap.
class MapEntityFocusCoordinator {
  String? _pendingEntityId;

  String? get pendingEntityId => _pendingEntityId;
  bool get hasPendingEntity => _pendingEntityId != null;

  void arm(RuntimeMapCameraTarget target) {
    final entityId = target.entityId.trim();
    final source = target.source.trim().toLowerCase();
    if (entityId.isEmpty || _isBrowseOnlyTarget(entityId, source)) {
      _pendingEntityId = null;
      return;
    }
    _pendingEntityId = entityId;
  }

  bool consume(String entityId) {
    if (_pendingEntityId != entityId.trim()) return false;
    _pendingEntityId = null;
    return true;
  }

  void cancel() => _pendingEntityId = null;

  bool _isBrowseOnlyTarget(String entityId, String source) {
    final normalizedId = entityId.toLowerCase();
    if (normalizedId == 'device-location' ||
        normalizedId == 'country-pack-ro' ||
        normalizedId == 'country-pack-uk') {
      return true;
    }
    return source == 'device-location' ||
        source.contains('selector') ||
        source.contains('utility') ||
        source.contains('control');
  }
}
