import 'package:flutter/foundation.dart';

@immutable
class RuntimeMapCameraTarget {
  const RuntimeMapCameraTarget({
    required this.source,
    required this.entityId,
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  final String source;
  final String entityId;
  final double latitude;
  final double longitude;
  final double zoom;

  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (latitude != 0 || longitude != 0);
}

RuntimeMapCameraTarget deviceLocationCameraTarget({
  required double latitude,
  required double longitude,
  required double zoom,
}) => RuntimeMapCameraTarget(
  source: 'device-location',
  entityId: 'device-location',
  latitude: latitude,
  longitude: longitude,
  zoom: zoom,
);

@immutable
class RuntimeMapCameraApplication {
  const RuntimeMapCameraApplication({
    required this.requestId,
    required this.target,
    required this.isReplay,
  });

  final int requestId;
  final RuntimeMapCameraTarget target;
  final bool isReplay;
}

/// Coordinates camera requests with the independent Mapbox map/style lifecycle.
///
/// A navigation request is consumed once. Its active runtime target can be
/// replayed after a style reload or tab re-entry without creating or consuming
/// another navigation request.
class PendingMapCameraCoordinator {
  int _nextRequestId = 0;
  int? _activeRequestId;
  int? _pendingRequestId;
  RuntimeMapCameraTarget? _activeTarget;
  bool _mapCreated = false;
  bool _styleReady = false;
  bool _needsApplication = false;
  bool _replayRequested = false;

  RuntimeMapCameraTarget? get activeTarget => _activeTarget;
  bool get isReady => _mapCreated && _styleReady;
  bool get hasPendingApplication => _needsApplication;

  int request(RuntimeMapCameraTarget target) {
    if (!target.hasValidCoordinates) {
      throw ArgumentError.value(target, 'target', 'Invalid map coordinates');
    }
    final requestId = ++_nextRequestId;
    _activeRequestId = requestId;
    _pendingRequestId = requestId;
    _activeTarget = target;
    _needsApplication = true;
    _replayRequested = false;
    return requestId;
  }

  void markMapCreated() {
    _mapCreated = true;
    _styleReady = false;
    _requestReplayIfActive();
  }

  void markMapDetached() {
    _mapCreated = false;
    _styleReady = false;
  }

  void markStyleLoading() {
    _styleReady = false;
  }

  void markStyleLoaded() {
    _styleReady = true;
    _requestReplayIfActive();
  }

  void markReentered() => _requestReplayIfActive();

  RuntimeMapCameraApplication? takeReadyApplication() {
    final requestId = _activeRequestId;
    final target = _activeTarget;
    if (!isReady || !_needsApplication || requestId == null || target == null) {
      return null;
    }
    final isReplay = _pendingRequestId == null || _replayRequested;
    _pendingRequestId = null;
    _needsApplication = false;
    _replayRequested = false;
    return RuntimeMapCameraApplication(
      requestId: requestId,
      target: target,
      isReplay: isReplay,
    );
  }

  void _requestReplayIfActive() {
    if (_activeTarget == null) return;
    _needsApplication = true;
    if (_pendingRequestId == null) _replayRequested = true;
  }
}
