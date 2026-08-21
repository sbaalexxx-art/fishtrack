import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../core/context/current_location.dart';
import '../core/context/selected_context.dart';
import '../core/map/fluviai_map_pin_system.dart';
import '../core/map/hydro_semantic_density.dart';
import '../core/map/map_feature_registry.dart';
import '../core/map/map_runtime_provenance.dart';
import '../core/map/hydro_ro_vector_overlay.dart';
import '../core/map/map_theme_style.dart';
import '../core/map/pending_map_camera.dart';
import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../core/navigation/map_entry.dart';
import '../core/navigation/water_entry.dart';
import '../core/water/water_history_analysis.dart';
import '../features/hydro_dispatch/presentation/hydro_dispatch_presentation.dart';
import '../l10n/l10n.dart';
import '../models/station.dart';
import '../models/water_asset.dart';
import '../models/water_level.dart';
import '../models/water_river.dart';
import '../services/community_service.dart';
import '../services/favorite_stations_service.dart';
import '../services/hydro_dispatch_service.dart';
import '../services/location_service.dart';
import '../services/water_service.dart';
import '../services/water_asset_service.dart';
import '../services/saved_items_service.dart';
import '../widgets/fluviai/draggable_ask_fluvi.dart';
import '../widgets/fluviai/hydro_intelligence_panel.dart';

enum _FullMapStyle {
  satellite(Icons.satellite_alt_rounded),
  standard(Icons.map_rounded),
  outdoors(Icons.terrain_rounded),
  streets(Icons.route_rounded);

  const _FullMapStyle(this.icon);

  final IconData icon;

  String get uri => switch (this) {
    _FullMapStyle.satellite => MapThemeStyle.satellite,
    _FullMapStyle.standard => MapThemeStyle.standard,
    _FullMapStyle.outdoors => MapThemeStyle.outdoors,
    _FullMapStyle.streets => MapThemeStyle.streets,
  };
}

enum _BoatNavigationState { off, ready, running, stopped }

@immutable
class MapFocusRequest {
  const MapFocusRequest({required this.id, required this.target, this.station});

  final int id;
  final RuntimeMapCameraTarget target;
  final Station? station;
}

/// One-shot bridge between the existing tab router and the persistent Map.
///
/// A request remains pending until the Map consumes it. Reopening the same
/// station creates a new request id, while [takePending] can return each
/// request only once.
class MapFocusController extends ChangeNotifier {
  int _nextRequestId = 0;
  MapFocusRequest? _pending;

  MapFocusRequest? get pending => _pending;

  void requestStation(Station station) {
    _pending = MapFocusRequest(
      id: ++_nextRequestId,
      station: station,
      target: RuntimeMapCameraTarget(
        source: 'water-navigation',
        entityId: station.id,
        latitude: station.latitude,
        longitude: station.longitude,
        zoom: 13.5,
      ),
    );
    logMapRuntime(
      'focus-controller.request',
      station: station,
      fields: {'focusRequestId': _pending!.id},
    );
    notifyListeners();
  }

  void requestTarget(RuntimeMapCameraTarget target) {
    _pending = MapFocusRequest(id: ++_nextRequestId, target: target);
    logMapRuntime(
      'focus-controller.request-target',
      fields: {
        'focusRequestId': _pending!.id,
        'source': target.source,
        'entityId': target.entityId,
      },
    );
    notifyListeners();
  }

  MapFocusRequest? takePending() {
    final request = _pending;
    _pending = null;
    if (request != null) {
      logMapRuntime(
        'focus-controller.consume',
        station: request.station,
        fields: {'focusRequestId': request.id, 'source': request.target.source},
      );
    }
    return request;
  }
}

/// A pushed, source-preserving presentation of the one production [MapPage].
///
/// General browsing remains the bottom-nav Map tab. Explicit entity/place
/// intents push this wrapper so Back deterministically returns to the caller.
class ContextualMapPage extends ConsumerStatefulWidget {
  const ContextualMapPage({super.key, required this.entry});

  final ContextualMapEntry? entry;

  @override
  ConsumerState<ContextualMapPage> createState() => _ContextualMapPageState();
}

class _ContextualMapPageState extends ConsumerState<ContextualMapPage> {
  late final ValueNotifier<bool> _active;
  late final MapFocusController _focusController;

  @override
  void initState() {
    super.initState();
    _active = ValueNotifier<bool>(true);
    _focusController = MapFocusController();
    final entry = widget.entry;
    final station = entry?.station;
    final target = entry?.cameraTarget;
    if (station != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(selectedContextProvider.notifier).selectStation(station);
        }
      });
      _focusController.requestStation(station);
    } else if (target != null) {
      _focusController.requestTarget(target);
    }
  }

  @override
  void dispose() {
    _active.dispose();
    _focusController.dispose();
    super.dispose();
  }

  Future<void> _openAddCatch() async {
    final added = await AppNavigator.open<bool>(
      context,
      AppDestination.addCatch,
    );
    if (mounted && added == true) {
      await AppNavigator.open<void>(context, AppDestination.myCatches);
    }
  }

  @override
  Widget build(BuildContext context) => MapPage(
    isActiveListenable: _active,
    focusController: _focusController,
    includeBottomSafeArea: true,
    onBack: () => Navigator.of(context).maybePop(),
    onAddCatch: _openAddCatch,
    onCreateReport: (category) => AppNavigator.open<void>(
      context,
      AppDestination.addReport,
      arguments: category,
    ),
  );
}

/// Returns dataset-wide station candidates for the Full Map annotation layer.
///
/// Monitoring-station coverage is independent from the device/local camera
/// radius. Local radius filtering belongs to contextual layers such as reports.
List<Station> filterFullMapStations({
  required Iterable<Station> stations,
  Set<String>? stationIds,
}) {
  final ids = stationIds;
  return stations
      .where((station) {
        if (ids != null && !ids.contains(station.id)) return false;
        if (!isValidRuntimeMapCoordinate(station.latitude, station.longitude)) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
}

const Color fullMapTemporaryStationHighlightColor = Color(0xFFFFD166);

List<CommunityPost> filterFullMapReports({
  required Iterable<CommunityPost> reports,
  required LatLng? center,
  required double radiusKm,
  required Set<ReportCategory> categories,
}) => reports
    .where((report) {
      final latitude = report.latitude;
      final longitude = report.longitude;
      if (latitude == null || longitude == null) return false;
      if (!isValidRuntimeMapCoordinate(latitude, longitude)) return false;
      final category = report.reportCategory;
      if (categories.isNotEmpty &&
          (category == null || !categories.contains(category))) {
        return false;
      }
      return _fullMapPointWithinRadius(
        latitude: latitude,
        longitude: longitude,
        center: center,
        radiusKm: radiusKm,
      );
    })
    .toList(growable: false);

List<CommunityPost> filterFullMapCatches({
  required Iterable<CommunityPost> catches,
  required LatLng? center,
  required double radiusKm,
}) => catches
    .where((catchPost) {
      if (catchPost.type != CommunityPostType.catchPost) return false;
      final latitude = catchPost.latitude;
      final longitude = catchPost.longitude;
      if (latitude == null || longitude == null) return false;
      if (!isValidRuntimeMapCoordinate(latitude, longitude)) return false;
      return _fullMapPointWithinRadius(
        latitude: latitude,
        longitude: longitude,
        center: center,
        radiusKm: radiusKm,
      );
    })
    .toList(growable: false);

bool isValidRuntimeMapCoordinate(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    (latitude != 0 || longitude != 0);

bool _fullMapPointWithinRadius({
  required double latitude,
  required double longitude,
  required LatLng? center,
  required double radiusKm,
}) {
  if (center == null || radiusKm.isInfinite) return true;
  const distance = Distance();
  return distance.as(
        LengthUnit.Kilometer,
        center,
        LatLng(latitude, longitude),
      ) <=
      radiusKm;
}

class MapPage extends ConsumerStatefulWidget {
  const MapPage({
    super.key,
    required this.isActiveListenable,
    required this.focusController,
    required this.onAddCatch,
    required this.onCreateReport,
    this.favoriteStationsService = const FavoriteStationsService(),
    this.includeBottomSafeArea = true,
    this.onBack,
  });

  final ValueListenable<bool> isActiveListenable;
  final MapFocusController focusController;
  final VoidCallback onAddCatch;
  final ValueChanged<ReportCategory> onCreateReport;
  final FavoriteStationsService favoriteStationsService;
  final bool includeBottomSafeArea;
  final VoidCallback? onBack;

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> with WidgetsBindingObserver {
  final WaterService _waterService = WaterService();
  final WaterAssetService _waterAssetService = const WaterAssetService();
  final HydroDispatchService _hydroDispatchService =
      const HydroDispatchService();
  final SavedItemsService _savedItemsService = const SavedItemsService();
  final CommunityService _communityService = const CommunityService();
  FavoriteStationsService get _favoriteStationsService =>
      widget.favoriteStationsService;
  final PendingMapCameraCoordinator _cameraCoordinator =
      PendingMapCameraCoordinator();

  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _stationAnnotationManager;
  mapbox.CircleAnnotationManager? _stationHighlightAnnotationManager;
  mapbox.CircleAnnotationManager? _userAnnotationManager;
  mapbox.CircleAnnotationManager? _reportAnnotationManager;
  mapbox.CircleAnnotationManager? _catchAnnotationManager;
  mapbox.CircleAnnotationManager? _waterAssetHaloAnnotationManager;
  mapbox.PointAnnotationManager? _waterAssetAnnotationManager;
  mapbox.CircleAnnotationManager? _hydropowerHaloAnnotationManager;
  mapbox.PointAnnotationManager? _hydropowerAnnotationManager;
  dynamic _stationTapEvents;
  dynamic _reportTapEvents;
  dynamic _catchTapEvents;
  dynamic _waterAssetTapEvents;
  dynamic _hydropowerTapEvents;

  List<Station> _stations = const [];
  List<CommunityPost> _activeReports = const [];
  List<CommunityPost> _publicCatches = const [];
  List<WaterAssetRef> _waterAssets = const [];
  List<WaterMapPin> _hydropowerPins = const [];
  Set<String> _favoriteStationIds = const {};
  Set<String> _savedWaterAssetKeys = const {};
  LatLng? _currentLocation;
  bool _isLocating = false;
  bool _isLoadingStations = false;
  bool _stationLayerVisible = true;
  bool _communityReportsVisible = true;
  bool _publicCatchesVisible = false;
  bool _favoriteStationsVisible = false;
  bool _damLayerVisible = true;
  bool _reservoirLayerVisible = true;
  bool _hydropowerLayerVisible = true;
  bool _isLoadingWaterAssets = false;
  double _localRadiusKm = 100;
  Set<ReportCategory> _reportCategories = const {};
  bool _hasLoadedInitialStyle = false;
  bool _isChangingMapStyle = false;
  bool _isCompletingStyleChange = false;
  _FullMapStyle _selectedMapStyle = _FullMapStyle.satellite;
  _FullMapStyle? _pendingMapStyle;
  mapbox.CameraState? _cameraBeforeStyleChange;
  Station? _temporarilyHighlightedStation;
  Station? _previewStation;
  WaterUiResult? _previewStationWaterResult;
  int _previewStationWaterRequestId = 0;
  WaterAssetRef? _previewWaterAsset;
  WaterAssetDetail? _previewWaterAssetDetail;
  WaterEntityState? _previewWaterAssetState;
  WaterMapPin? _previewHydropowerPin;
  HydropowerPlantState? _previewHydropowerState;
  HydroMapDispatchSnapshot? _previewHydroDispatchSnapshot;
  HydroOverlayPreferences _hydroPreferences = const HydroOverlayPreferences();
  HydroPublicFeatureSelection? _hydroPublicSelection;
  WaterRiverRef? _previewRiver;
  WaterRiverDetail? _previewRiverDetail;
  WaterEntityState? _previewRiverState;
  bool _isLoadingHydroSelection = false;
  bool _isHydroPanelExpanded = false;
  double _cameraZoom = 5.65;
  String? _stationLoadError;
  String? _waterAssetLoadError;
  LatLng? _lastWaterAssetQueryCenter;
  double? _lastWaterAssetQueryRadiusKm;
  final Set<String> _registeredWaterAssetStyleImageIds = <String>{};
  String? _stationAnnotationFingerprint;
  String? _waterAssetAnnotationFingerprint;
  String? _hydropowerAnnotationFingerprint;
  Timer? _stationRefreshTimer;
  StreamSubscription<CurrentDeviceLocation>? _boatNavigationSubscription;
  _BoatNavigationState _boatNavigationState = _BoatNavigationState.off;
  bool _isFullMapActive = false;
  bool _hasSelectedStationFocus = false;
  String? _locationUnavailableMessage;
  double? _gpsSpeedKmh;
  double? _gpsHeadingDegrees;
  Orientation? _orientation;
  Size? _mediaSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFullMapActive = widget.isActiveListenable.value;
    widget.isActiveListenable.addListener(_handleMapActiveChanged);
    widget.focusController.addListener(_consumePendingFocus);
    _consumePendingFocus();
    _loadStations();
    _loadApprovedMapLayers();
    _updateStationRefreshTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
  }

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.isActiveListenable, widget.isActiveListenable)) {
      if (!identical(oldWidget.focusController, widget.focusController)) {
        oldWidget.focusController.removeListener(_consumePendingFocus);
        widget.focusController.addListener(_consumePendingFocus);
        _consumePendingFocus();
      }
      return;
    }

    oldWidget.isActiveListenable.removeListener(_handleMapActiveChanged);
    _isFullMapActive = widget.isActiveListenable.value;
    widget.isActiveListenable.addListener(_handleMapActiveChanged);
    if (!identical(oldWidget.focusController, widget.focusController)) {
      oldWidget.focusController.removeListener(_consumePendingFocus);
      widget.focusController.addListener(_consumePendingFocus);
      _consumePendingFocus();
    }
    _updateStationRefreshTimer();
    if (_isFullMapActive) {
      unawaited(_loadStations());
      unawaited(_loadApprovedMapLayers());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isFullMapActive) {
      _cameraCoordinator.markReentered();
      unawaited(_applyPendingCameraIfReady());
      unawaited(_loadStations());
      unawaited(_loadApprovedMapLayers());
      return;
    }

    // Never keep Boat navigation tracking alive in the background.
    if (state != AppLifecycleState.resumed &&
        _boatNavigationState == _BoatNavigationState.running) {
      unawaited(_stopBoatNavigation(close: false));
    }
  }

  void _handleMapActiveChanged() {
    final isActive = widget.isActiveListenable.value;
    if (_isFullMapActive == isActive) return;

    _isFullMapActive = isActive;
    _updateStationRefreshTimer();

    if (isActive) {
      _cameraCoordinator.markReentered();
      unawaited(_applyPendingCameraIfReady());
      unawaited(_loadStations());
      unawaited(_loadApprovedMapLayers());
      return;
    }

    // Leaving Full Map always terminates the explicit navigation session.
    if (_boatNavigationState != _BoatNavigationState.off) {
      unawaited(_stopBoatNavigation(close: true));
    }
  }

  void _toggleBoatNavigationPanel() {
    if (!_isFullMapActive) return;

    if (_boatNavigationState == _BoatNavigationState.off) {
      setState(() {
        _boatNavigationState = _BoatNavigationState.ready;
        _gpsSpeedKmh = null;
        _gpsHeadingDegrees = null;
      });
      return;
    }

    unawaited(_stopBoatNavigation(close: true));
  }

  Future<void> _startBoatNavigation() async {
    if (!_isFullMapActive ||
        _boatNavigationState == _BoatNavigationState.running) {
      return;
    }

    final previous = _boatNavigationSubscription;
    _boatNavigationSubscription = null;
    if (previous != null) {
      await previous.cancel();
    }

    if (!mounted) return;

    setState(() {
      _boatNavigationState = _BoatNavigationState.running;
      _gpsSpeedKmh = null;
      _gpsHeadingDegrees = null;
    });

    final stream = const LocationService().watchNavigationCoordinates();

    _boatNavigationSubscription = stream.listen(
      _handleBoatNavigationLocation,
      onError: _handleBoatNavigationError,
      cancelOnError: true,
    );
  }

  void _handleBoatNavigationLocation(CurrentDeviceLocation location) {
    if (!mounted || _boatNavigationState != _BoatNavigationState.running) {
      return;
    }

    setState(() {
      _currentLocation = LatLng(location.latitude, location.longitude);
      _gpsSpeedKmh = location.speedMetersPerSecond == null
          ? null
          : location.speedMetersPerSecond! * 3.6;
      _gpsHeadingDegrees = location.headingDegrees;
      _locationUnavailableMessage = null;
    });

    unawaited(_syncUserAnnotation());
  }

  void _handleBoatNavigationError(Object error, StackTrace stackTrace) {
    final subscription = _boatNavigationSubscription;
    _boatNavigationSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    if (!mounted) return;

    setState(() {
      _boatNavigationState = _BoatNavigationState.stopped;
      _gpsSpeedKmh = null;
      _gpsHeadingDegrees = null;
    });

    final message = error is LocationFailure
        ? switch (error.reason) {
            LocationFailureReason.serviceDisabled =>
              context.l10n.locationRequired,
            LocationFailureReason.permissionDenied =>
              context.l10n.locationRequired,
            LocationFailureReason.permissionDeniedForever =>
              context.l10n.locationRequired,
            LocationFailureReason.unavailable => context.l10n.notAvailable,
          }
        : context.l10n.notAvailable;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopBoatNavigation({required bool close}) async {
    final subscription = _boatNavigationSubscription;
    _boatNavigationSubscription = null;

    if (subscription != null) {
      await subscription.cancel();
    }

    if (!mounted) return;

    setState(() {
      _gpsSpeedKmh = null;
      _gpsHeadingDegrees = null;
      _boatNavigationState = close
          ? _BoatNavigationState.off
          : _BoatNavigationState.stopped;
    });
  }

  Future<void> _toggleFavorite(Station station) async {
    final shouldFavorite = !_favoriteStationIds.contains(station.id);
    try {
      await _favoriteStationsService.setFavorite(
        station.id,
        favorite: shouldFavorite,
      );
      if (!mounted) return;
      setState(() {
        final next = {..._favoriteStationIds};
        shouldFavorite ? next.add(station.id) : next.remove(station.id);
        _favoriteStationIds = next;
      });
      await _syncStationAnnotations();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldFavorite
                ? 'Stația a fost adăugată la Favorite.'
                : 'Stația a fost eliminată din Favorite.',
          ),
        ),
      );
    } on FavoriteException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  void _updateStationRefreshTimer() {
    _stationRefreshTimer?.cancel();
    _stationRefreshTimer = null;
    if (!_isFullMapActive) return;

    _stationRefreshTimer = Timer.periodic(WaterService.cacheDuration, (_) {
      if (!mounted || !_isFullMapActive) return;
      unawaited(_loadStations());
      unawaited(_loadApprovedMapLayers());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final orientation = MediaQuery.orientationOf(context);
    final mediaSize = MediaQuery.sizeOf(context);
    if (_orientation == orientation && _mediaSize == mediaSize) return;
    _orientation = orientation;
    _mediaSize = mediaSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapboxMap = _mapboxMap;
      if (mounted && mapboxMap != null) {
        unawaited(_updateMapboxOrnaments(mapboxMap));
      }
    });
  }

  @override
  void dispose() {
    _stationRefreshTimer?.cancel();
    final boatSubscription = _boatNavigationSubscription;
    _boatNavigationSubscription = null;
    if (boatSubscription != null) {
      unawaited(boatSubscription.cancel());
    }
    widget.isActiveListenable.removeListener(_handleMapActiveChanged);
    widget.focusController.removeListener(_consumePendingFocus);
    WidgetsBinding.instance.removeObserver(this);
    _stationTapEvents?.cancel();
    _reportTapEvents?.cancel();
    _catchTapEvents?.cancel();
    _waterAssetTapEvents?.cancel();
    _hydropowerTapEvents?.cancel();
    _stationAnnotationManager?.deleteAll();
    _stationHighlightAnnotationManager?.deleteAll();
    _userAnnotationManager?.deleteAll();
    _reportAnnotationManager?.deleteAll();
    _catchAnnotationManager?.deleteAll();
    _waterAssetHaloAnnotationManager?.deleteAll();
    _waterAssetAnnotationManager?.deleteAll();
    _hydropowerHaloAnnotationManager?.deleteAll();
    _hydropowerAnnotationManager?.deleteAll();
    _cameraCoordinator.markMapDetached();
    super.dispose();
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _cameraCoordinator.markMapCreated();
    logMapRuntime('map.created-style-pending');

    await _updateMapboxOrnaments(mapboxMap);
    await _applyPendingCameraIfReady();
  }

  void _consumePendingFocus() {
    final request = widget.focusController.takePending();
    if (request == null) return;
    if (request.target.source == 'hydro-ro-utility') {
      _hydroPreferences = _hydroPreferences.copyWith(enabled: true);
      unawaited(
        ref
            .read(contentRegionProvider.notifier)
            .selectCountry(countryCode: 'RO', region: 'România'),
      );
      unawaited(_applyHydroRuntime());
    }
    final station = request.station;
    _hasSelectedStationFocus = station != null;
    _locationUnavailableMessage = null;
    final cameraRequestId = _cameraCoordinator.request(request.target);
    logMapRuntime(
      'map.focus-consumed',
      station: station,
      fields: {
        'focusRequestId': request.id,
        'cameraRequestId': cameraRequestId,
      },
    );
    if (mounted && station != null) {
      setState(() {
        _stationLayerVisible = true;
        _temporarilyHighlightedStation = station;
        _previewStation = station;
      });
    } else if (station != null) {
      _stationLayerVisible = true;
      _temporarilyHighlightedStation = station;
      _previewStation = station;
    } else if (mounted) {
      setState(() {
        _temporarilyHighlightedStation = null;
        _previewStation = null;
      });
    }
    if (station != null) {
      unawaited(_loadPreviewStationWater(station));
    }
    unawaited(_applyPendingCameraIfReady());
    unawaited(_syncStationAnnotations());
    unawaited(_syncReportAnnotations());
    unawaited(_syncCatchAnnotations());
  }

  void _onStyleLoaded(mapbox.StyleLoadedEventData _) {
    _cameraCoordinator.markStyleLoaded();
    if (mounted) setState(() => _hasLoadedInitialStyle = true);
    _isCompletingStyleChange = true;
    logMapRuntime('map.style-loaded');
    unawaited(_restoreRuntimeAfterStyleLoad());
  }

  Future<void> _loadPreviewStationWater(Station station) async {
    final requestId = ++_previewStationWaterRequestId;
    final cached = _waterService.cachedWaterUiResult(
      station,
      historyWindow: const Duration(hours: 24),
    );
    if (mounted && _previewStation?.id == station.id) {
      setState(() => _previewStationWaterResult = cached);
    }

    late final WaterUiResult result;
    try {
      result = await _waterService.getWaterUiResult(
        station,
        historyWindow: const Duration(hours: 24),
      );
    } on Object {
      return;
    }
    if (!mounted ||
        requestId != _previewStationWaterRequestId ||
        _previewStation?.id != station.id) {
      return;
    }
    setState(() => _previewStationWaterResult = result);
  }

  Future<void> _restoreRuntimeAfterStyleLoad() async {
    final mapboxMap = _mapboxMap;

    if (mapboxMap != null && _effectiveHydroPreferences.enabled) {
      try {
        await HydroRoMapboxOverlay.bind(
          mapboxMap,
          preferences: _effectiveHydroPreferences,
          selection: _hydroPublicSelection,
          satelliteBasemap: _selectedMapStyle == _FullMapStyle.satellite,
        );
        logMapRuntime('map.hydro-ro-overlay-bound');
      } on Object {
        // A Hydro overlay failure must not block the base map,
        // camera restoration or the existing annotation managers.
        logMapRuntime('map.hydro-ro-overlay-bind-failed');
      }
    }

    await _restoreAfterStyleChange();
  }

  Future<void> _bindAnnotationManagers(
    mapbox.MapboxMap mapboxMap, {
    bool replaceExisting = false,
  }) async {
    if (!_cameraCoordinator.isReady) return;
    if (!replaceExisting &&
        _stationAnnotationManager != null &&
        _stationHighlightAnnotationManager != null &&
        _userAnnotationManager != null &&
        _reportAnnotationManager != null &&
        _catchAnnotationManager != null &&
        _waterAssetHaloAnnotationManager != null &&
        _waterAssetAnnotationManager != null &&
        _hydropowerHaloAnnotationManager != null &&
        _hydropowerAnnotationManager != null) {
      return;
    }

    if (replaceExisting) {
      await _releaseAnnotationManagers(mapboxMap);
    }

    _stationAnnotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();
    try {
      _stationTapEvents = _stationAnnotationManager?.tapEvents(
        onTap: _handleStationAnnotationTap,
      );
      _stationHighlightAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _userAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _reportAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _reportTapEvents = _reportAnnotationManager?.tapEvents(
        onTap: _handleReportAnnotationTap,
      );
      _catchAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _catchTapEvents = _catchAnnotationManager?.tapEvents(
        onTap: _handleCatchAnnotationTap,
      );
      _waterAssetHaloAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _waterAssetAnnotationManager = await mapboxMap.annotations
          .createPointAnnotationManager();
      _waterAssetTapEvents = _waterAssetAnnotationManager?.tapEvents(
        onTap: _handleWaterAssetAnnotationTap,
      );
      _hydropowerHaloAnnotationManager = await mapboxMap.annotations
          .createCircleAnnotationManager();
      _hydropowerAnnotationManager = await mapboxMap.annotations
          .createPointAnnotationManager();
      _hydropowerTapEvents = _hydropowerAnnotationManager?.tapEvents(
        onTap: _handleHydropowerAnnotationTap,
      );

      await _syncStationAnnotations();
      await _syncUserAnnotation();
      await _syncReportAnnotations();
      await _syncCatchAnnotations();
      await _syncWaterAssetAnnotations();
      await _syncHydropowerAnnotations();
    } catch (_) {
      await _releaseAnnotationManagers(mapboxMap);
      rethrow;
    }
  }

  Future<void> _releaseAnnotationManagers(mapbox.MapboxMap mapboxMap) async {
    final stationManager = _stationAnnotationManager;
    final highlightManager = _stationHighlightAnnotationManager;
    final userManager = _userAnnotationManager;
    final reportManager = _reportAnnotationManager;
    final catchManager = _catchAnnotationManager;
    final waterAssetHaloManager = _waterAssetHaloAnnotationManager;
    final waterAssetManager = _waterAssetAnnotationManager;
    final hydropowerHaloManager = _hydropowerHaloAnnotationManager;
    final hydropowerManager = _hydropowerAnnotationManager;

    await _stationTapEvents?.cancel();
    await _reportTapEvents?.cancel();
    await _catchTapEvents?.cancel();
    await _waterAssetTapEvents?.cancel();
    await _hydropowerTapEvents?.cancel();
    _stationTapEvents = null;
    _reportTapEvents = null;
    _catchTapEvents = null;
    _waterAssetTapEvents = null;
    _hydropowerTapEvents = null;
    _stationAnnotationManager = null;
    _stationHighlightAnnotationManager = null;
    _userAnnotationManager = null;
    _reportAnnotationManager = null;
    _catchAnnotationManager = null;
    _waterAssetHaloAnnotationManager = null;
    _waterAssetAnnotationManager = null;
    _hydropowerHaloAnnotationManager = null;
    _hydropowerAnnotationManager = null;
    _stationAnnotationFingerprint = null;
    _waterAssetAnnotationFingerprint = null;
    _hydropowerAnnotationFingerprint = null;
    _registeredWaterAssetStyleImageIds.clear();

    for (final manager in [
      stationManager,
      highlightManager,
      userManager,
      reportManager,
      catchManager,
      waterAssetHaloManager,
      waterAssetManager,
      hydropowerHaloManager,
      hydropowerManager,
    ]) {
      if (manager == null) continue;
      try {
        await mapboxMap.annotations.removeAnnotationManager(manager);
      } catch (_) {
        // A completed style load may already have released the native manager.
      }
    }
  }

  Future<void> _restoreAfterStyleChange() async {
    final mapboxMap = _mapboxMap;
    final pendingStyle = _pendingMapStyle;
    final camera = _cameraBeforeStyleChange;
    if (mapboxMap == null) {
      _finishStyleChange();
      return;
    }

    var restoreFailed = false;
    try {
      if (_cameraCoordinator.activeTarget == null && camera != null) {
        await mapboxMap.setCamera(
          mapbox.CameraOptions(
            center: camera.center,
            padding: camera.padding,
            zoom: camera.zoom,
            bearing: camera.bearing,
            pitch: camera.pitch,
          ),
        );
      }
    } catch (_) {
      restoreFailed = true;
    }
    try {
      await _updateMapboxOrnaments(mapboxMap);
    } catch (_) {
      restoreFailed = true;
    }
    try {
      await _bindAnnotationManagers(mapboxMap, replaceExisting: true);
    } catch (_) {
      restoreFailed = true;
    }
    try {
      await _applyPendingCameraIfReady();
    } catch (_) {
      restoreFailed = true;
    }

    if (restoreFailed && mounted) {
      _showStyleChangeError();
    }
    if (!mounted) {
      _finishStyleChange();
      return;
    }
    setState(() {
      if (pendingStyle != null) _selectedMapStyle = pendingStyle;
      _isChangingMapStyle = false;
      _isCompletingStyleChange = false;
      _pendingMapStyle = null;
      _cameraBeforeStyleChange = null;
    });
  }

  void _finishStyleChange() {
    _isChangingMapStyle = false;
    _isCompletingStyleChange = false;
    _pendingMapStyle = null;
    _cameraBeforeStyleChange = null;
  }

  Future<void> _updateMapboxOrnaments(mapbox.MapboxMap mapboxMap) async {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    await mapboxMap.scaleBar.updateSettings(
      mapbox.ScaleBarSettings(
        position: mapbox.OrnamentPosition.BOTTOM_RIGHT,
        marginRight: 12,
        marginBottom: 12,
        ratio: isLandscape ? .24 : .3,
      ),
    );
  }

  Future<void> _loadStations() async {
    if (_isLoadingStations) return;
    setState(() {
      _isLoadingStations = true;
      _stationLoadError = null;
    });

    try {
      final stations = await _waterService.getStations();
      if (!mounted) return;
      setState(() => _stations = stations);
      logMapRuntime(
        'layers.stations-fetched',
        fields: {'count': stations.length},
      );
      await _syncStationAnnotations();
    } on Exception {
      if (!mounted) return;
      setState(() => _stationLoadError = context.l10n.waterProviderUnavailable);
    } finally {
      if (mounted) setState(() => _isLoadingStations = false);
    }
  }

  Future<void> _loadApprovedMapLayers() async {
    List<CommunityPost> reports = _activeReports;
    List<CommunityPost> catches = _publicCatches;
    Set<String> favorites = _favoriteStationIds;
    try {
      final feed = await _communityService.getFeed();
      reports = feed
          .where(
            (post) =>
                post.isActiveReport &&
                post.latitude != null &&
                post.longitude != null,
          )
          .toList(growable: false);
      catches = feed
          .where(
            (post) =>
                post.type == CommunityPostType.catchPost &&
                post.latitude != null &&
                post.longitude != null,
          )
          .toList(growable: false);
    } on Exception {
      // Keep the last truthful community snapshots when the feed is unavailable.
    }
    if (_favoriteStationsService.isAuthenticated) {
      try {
        favorites = await _favoriteStationsService.getFavoriteIds();
      } on FavoriteException {
        // Other approved layers stay usable when favorites are unavailable.
      }
    } else {
      favorites = const {};
    }
    if (!mounted) return;
    setState(() {
      _activeReports = reports;
      _publicCatches = catches;
      _favoriteStationIds = favorites;
    });
    logMapRuntime(
      'layers.repositories-fetched',
      fields: {
        'reports': reports.length,
        'catches': catches.length,
        'favorites': favorites.length,
      },
    );
    await _syncStationAnnotations();
    await _syncReportAnnotations();
    await _syncCatchAnnotations();
  }

  bool get _hasPremiumWater =>
      ref.read(fluviAccessTierProvider) == FluviAccessTier.premium;

  HydroOverlayPreferences get _effectiveHydroPreferences => _hydroPreferences
      .copyWith(enabled: _hydroPreferences.enabled && _hasPremiumWater);

  Future<void> _applyHydroRuntime() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_cameraCoordinator.isReady) return;
    try {
      if (_effectiveHydroPreferences.enabled) {
        final sourceExists = await mapboxMap.style.styleSourceExists(
          HydroRoMapboxOverlay.sourceId,
        );
        if (sourceExists) {
          await HydroRoMapboxOverlay.applyConfiguration(
            mapboxMap,
            preferences: _effectiveHydroPreferences,
            selection: _hydroPublicSelection,
            satelliteBasemap: _selectedMapStyle == _FullMapStyle.satellite,
          );
        } else {
          await HydroRoMapboxOverlay.bind(
            mapboxMap,
            preferences: _effectiveHydroPreferences,
            selection: _hydroPublicSelection,
            satelliteBasemap: _selectedMapStyle == _FullMapStyle.satellite,
          );
        }
      } else if (await mapboxMap.style.styleSourceExists(
        HydroRoMapboxOverlay.sourceId,
      )) {
        await HydroRoMapboxOverlay.applyConfiguration(
          mapboxMap,
          preferences: _effectiveHydroPreferences,
          selection: null,
          satelliteBasemap: _selectedMapStyle == _FullMapStyle.satellite,
        );
      }
    } on Object {
      logMapRuntime('map.hydro-ro-overlay-update-failed');
    }
  }

  Future<void> _loadWaterAssetsForCenter(
    LatLng center, {
    double? zoom,
    bool force = false,
  }) async {
    if (!_hasPremiumWater || !_hydroPreferences.enabled) {
      if ((_waterAssets.isNotEmpty || _hydropowerPins.isNotEmpty) && mounted) {
        setState(() {
          _waterAssets = const [];
          _hydropowerPins = const [];
          _previewWaterAsset = null;
          _previewHydropowerPin = null;
          _previewHydropowerState = null;
          _waterAssetLoadError = null;
        });
        await _syncWaterAssetAnnotations();
        await _syncHydropowerAnnotations();
      }
      return;
    }
    if (_isLoadingWaterAssets) return;
    final effectiveZoom = zoom ?? 11.5;
    if (effectiveZoom < 5) {
      if ((_waterAssets.isNotEmpty || _hydropowerPins.isNotEmpty) && mounted) {
        setState(() {
          _waterAssets = const [];
          _hydropowerPins = const [];
          _previewWaterAsset = null;
          _previewHydropowerPin = null;
          _previewHydropowerState = null;
          _waterAssetLoadError = null;
        });
        await _syncWaterAssetAnnotations();
        await _syncHydropowerAnnotations();
      }
      return;
    }
    final radiusKm = _waterAssetRadiusForZoom(effectiveZoom);
    final previous = _lastWaterAssetQueryCenter;
    final previousRadius = _lastWaterAssetQueryRadiusKm;
    if (!force && previous != null && previousRadius == radiusKm) {
      const distance = Distance();
      final movedKm = distance.as(LengthUnit.Kilometer, previous, center);
      if (movedKm < (radiusKm * .22).clamp(2.0, 18.0)) return;
    }

    if (mounted) {
      setState(() {
        _isLoadingWaterAssets = true;
        _waterAssetLoadError = null;
      });
    }
    try {
      final pins = await _waterAssetService.getMapPins(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusKm: radiusKm,
        zoom: effectiveZoom,
        limit: effectiveZoom >= 12
            ? 650
            : effectiveZoom >= 9
            ? 500
            : 350,
      );
      final assets = pins
          .map((pin) => pin.toWaterAssetRef())
          .whereType<WaterAssetRef>()
          .toList(growable: false);
      var hydropowerPins = pins
          .where((pin) => pin.isHydropower)
          .toList(growable: false);

      Set<String> savedKeys = _savedWaterAssetKeys;
      if (_savedItemsService.isAuthenticated) {
        try {
          final items = await _savedItemsService.getItems();
          savedKeys = items
              .where(
                (item) =>
                    item.type == 'dam' ||
                    item.type == 'reservoir' ||
                    item.type == 'hydropower' ||
                    item.type == 'river',
              )
              .map((item) => '${item.type}:${item.referenceId}')
              .toSet();
        } on Exception {
          // Keep the last saved state when favorites are temporarily unavailable.
        }
      }
      if (!mounted) return;
      final activeEntityId = _cameraCoordinator.activeTarget?.entityId;
      WaterAssetRef? focusedAsset;
      WaterMapPin? focusedHydropower;
      HydropowerPlantState? focusedHydropowerState;
      if (activeEntityId != null) {
        for (final asset in assets) {
          if (asset.id == activeEntityId) {
            focusedAsset = asset;
            break;
          }
        }
        if (focusedAsset == null) {
          for (final pin in hydropowerPins) {
            if (pin.entityId == activeEntityId) {
              focusedHydropower = pin;
              break;
            }
          }
        }
        final activeTarget = _cameraCoordinator.activeTarget;
        if (focusedAsset == null &&
            focusedHydropower == null &&
            activeTarget?.source == 'global-search-hydropower') {
          final state = await _waterAssetService.getHydropowerPlantState(
            activeEntityId,
          );
          if (state?.latitude != null && state?.longitude != null) {
            focusedHydropowerState = state;
            final selected = ref.read(selectedContextProvider);
            focusedHydropower = waterMapPinFromHydropowerState(
              state!,
              riverName: selected?.hydropowerPlantId == activeEntityId
                  ? selected?.riverName
                  : null,
            );
            hydropowerPins = <WaterMapPin>[
              ...hydropowerPins,
              focusedHydropower,
            ];
          }
        }
      }
      setState(() {
        _waterAssets = assets;
        _hydropowerPins = hydropowerPins;
        _savedWaterAssetKeys = savedKeys;
        _lastWaterAssetQueryCenter = center;
        _lastWaterAssetQueryRadiusKm = radiusKm;
        if (focusedAsset != null) _previewWaterAsset = focusedAsset;
        if (focusedHydropower != null) {
          _previewHydropowerPin = focusedHydropower;
          _previewHydropowerState = focusedHydropowerState;
          _previewHydroDispatchSnapshot = null;
          _isLoadingHydroSelection = true;
        }
      });
      logMapRuntime(
        'layers.water-map-pins-fetched',
        fields: {
          'count': pins.length,
          'radiusKm': radiusKm,
          'zoom': effectiveZoom,
          'dams': assets.where((a) => a.type == WaterAssetType.dam).length,
          'reservoirs': assets
              .where((a) => a.type == WaterAssetType.reservoir)
              .length,
          'hydropower': hydropowerPins.length,
        },
      );
      await _syncWaterAssetAnnotations();
      await _syncHydropowerAnnotations();
      if (focusedHydropower != null) {
        _publishHydropowerContext(focusedHydropower);
        unawaited(_refreshHydropowerPreview(focusedHydropower));
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _waterAssetLoadError =
            'Water Intelligence nu este disponibil momentan.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingWaterAssets = false);
    }
  }

  double _waterAssetRadiusForZoom(double zoom) {
    if (zoom >= 13) return 25;
    if (zoom >= 11) return 55;
    if (zoom >= 9.5) return 100;
    if (zoom >= 7.5) return 180;
    if (zoom >= 6) return 280;
    return 420;
  }

  Future<void> _handleMapIdle(mapbox.MapIdleEventData _) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap != null) {
      try {
        final camera = await mapboxMap.getCameraState();
        if (mounted && _cameraZoom != camera.zoom) {
          setState(() => _cameraZoom = camera.zoom);
          await _syncStationAnnotations();
          await _syncWaterAssetAnnotations();
          await _syncHydropowerAnnotations();
        }
      } on Object {
        // Camera telemetry is advisory; map interaction remains available.
      }
    }
    await _refreshWaterAssetsAtCamera();
  }

  Future<void> _handleHydroMapTap(
    mapbox.MapContentGestureContext gesture,
  ) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_effectiveHydroPreferences.enabled) return;
    if (_tapHitsHydroAnnotation(gesture)) {
      // Point-annotation callbacks own these taps. Without this guard the
      // underlying river geometry can win the same gesture and replace the
      // selected dam, reservoir, station, or hydropower plant.
      return;
    }
    HydroPublicFeatureSelection? selection;
    try {
      selection = await HydroRoMapboxOverlay.queryFeature(
        mapboxMap,
        gesture,
        preferences: _effectiveHydroPreferences,
      );
    } on Object {
      return;
    }
    if (selection == null || !mounted) return;

    setState(() {
      _hydroPublicSelection = selection;
      _previewRiver = null;
      _previewRiverDetail = null;
      _previewRiverState = null;
      _previewStation = null;
      _temporarilyHighlightedStation = null;
      _previewWaterAsset = null;
      _previewWaterAssetDetail = null;
      _previewWaterAssetState = null;
      _previewHydropowerPin = null;
      _previewHydropowerState = null;
      _isLoadingHydroSelection = true;
      _isHydroPanelExpanded = false;
    });
    ref
        .read(selectedContextProvider.notifier)
        .select(
          SelectedContext(
            countryCode: 'RO',
            locationName: selection.displayName,
            latitude: selection.latitude,
            longitude: selection.longitude,
            waterName: selection.displayName,
            riverName: selection.type == HydroPublicFeatureType.river
                ? selection.displayName
                : null,
            source: 'Mapbox public geometry',
          ),
        );
    await _applyHydroRuntime();

    final minimumZoom = switch (selection.type) {
      HydroPublicFeatureType.river => HydroRoMapboxOverlay.riverMinimumZoom(
        selection.displayName,
      ),
      HydroPublicFeatureType.reservoir => 8.2,
      HydroPublicFeatureType.dam => 10.3,
    };
    try {
      await mapboxMap.easeTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              selection.longitude,
              selection.latitude,
            ),
          ),
          zoom: _cameraZoom < minimumZoom ? minimumZoom : _cameraZoom,
        ),
        mapbox.MapAnimationOptions(duration: 520),
      );
    } on Object {
      // Selection remains valid when a camera animation is interrupted.
    }
    await _resolveHydroPublicSelection(selection);
  }

  bool _tapHitsHydroAnnotation(mapbox.MapContentGestureContext gesture) {
    final latitude = gesture.point.coordinates.lat.toDouble();
    final longitude = gesture.point.coordinates.lng.toDouble();
    final metersPerPixel =
        156543.03392 *
        math.cos(latitude * math.pi / 180) /
        math.pow(2, _cameraZoom);
    final hitRadiusMeters = (metersPerPixel * 44).clamp(90.0, 32000.0);
    const distance = Distance();
    final tap = LatLng(latitude, longitude);

    bool hits(double candidateLatitude, double candidateLongitude) =>
        distance.as(
          LengthUnit.Meter,
          tap,
          LatLng(candidateLatitude, candidateLongitude),
        ) <=
        hitRadiusMeters;

    return _visibleStations.any(
          (station) => hits(station.latitude, station.longitude),
        ) ||
        _visibleWaterAssets.any(
          (asset) => hits(asset.latitude, asset.longitude),
        ) ||
        _visibleHydropowerPins.any((pin) => hits(pin.latitude, pin.longitude));
  }

  Future<void> _resolveHydroPublicSelection(
    HydroPublicFeatureSelection selection,
  ) async {
    try {
      if (selection.type == HydroPublicFeatureType.river) {
        final candidates = await _waterAssetService.searchRivers(
          selection.displayName,
          limit: 16,
        );
        final river = _bestRiverMatch(candidates, selection.displayName);
        if (river == null || !mounted) return;

        WaterRiverDetail? detail;
        WaterEntityState? state;
        try {
          detail = await _waterAssetService.getRiverDetail(river);
        } on Exception {
          // Canonical identity remains useful when optional detail is absent.
        }
        try {
          state = await _waterAssetService.getRiverState(river);
        } on Exception {
          // UNKNOWN is rendered when no verified state is available.
        }
        if (!mounted || _hydroPublicSelection != selection) return;
        setState(() {
          _previewRiver = river;
          _previewRiverDetail = detail;
          _previewRiverState = state;
        });
        ref
            .read(selectedContextProvider.notifier)
            .select(
              SelectedContext(
                countryCode: river.countryCode,
                locationName: selection.displayName,
                latitude: selection.latitude,
                longitude: selection.longitude,
                waterId: river.waterBodyId,
                waterName: river.name,
                riverName: river.name,
                riverKey: river.key,
                source: river.provenanceSource,
              ),
            );
        return;
      }

      final candidates = await _waterAssetService.searchAssets(
        selection.displayName,
        limit: 24,
      );
      final expectedType = selection.type == HydroPublicFeatureType.dam
          ? WaterAssetType.dam
          : WaterAssetType.reservoir;
      final asset = _bestAssetMatch(
        candidates,
        selection.displayName,
        expectedType,
      );
      if (asset == null || !mounted) return;
      await _selectWaterAsset(asset, preservePublicSelection: true);
    } on Exception {
      // Public vector identity remains selectable when optional intelligence
      // lookup is unavailable. The panel renders the explicit UNKNOWN state.
    } finally {
      if (mounted && _hydroPublicSelection == selection) {
        setState(() => _isLoadingHydroSelection = false);
      }
    }
  }

  WaterRiverRef? _bestRiverMatch(
    Iterable<WaterRiverRef> candidates,
    String displayName,
  ) {
    final target = displayName.trim().toLowerCase();
    for (final river in candidates) {
      if (river.name.trim().toLowerCase() == target) return river;
    }
    if (HydroRoMapboxOverlay.isDanubeName(displayName)) {
      for (final river in candidates) {
        if (HydroRoMapboxOverlay.isDanubeName(river.name)) return river;
      }
    }
    return null;
  }

  WaterAssetRef? _bestAssetMatch(
    Iterable<WaterAssetRef> candidates,
    String displayName,
    WaterAssetType expectedType,
  ) {
    final target = displayName.trim().toLowerCase();
    for (final asset in candidates) {
      if (asset.type == expectedType &&
          asset.name.trim().toLowerCase() == target) {
        return asset;
      }
    }
    return null;
  }

  Future<void> _refreshWaterAssetsAtCamera({bool force = false}) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_cameraCoordinator.isReady) return;
    try {
      final camera = await mapboxMap.getCameraState();
      final center = LatLng(
        camera.center.coordinates.lat.toDouble(),
        camera.center.coordinates.lng.toDouble(),
      );
      await _loadWaterAssetsForCenter(center, zoom: camera.zoom, force: force);
    } on Exception {
      // Base map remains usable even when contextual Water discovery fails.
    }
  }

  LatLng? get _activeFilterCenter {
    final station = _previewStation ?? _temporarilyHighlightedStation;
    if (station != null) return LatLng(station.latitude, station.longitude);
    final target = _cameraCoordinator.activeTarget;
    if (target != null) return LatLng(target.latitude, target.longitude);
    return _currentLocation;
  }

  List<Station> get _visibleStations {
    final valid = filterFullMapStations(stations: _stations);
    if (_cameraZoom < 7.2) return const <Station>[];
    if (_cameraZoom >= 9) return valid;
    return valid
        .where(
          (station) =>
              HydroRoMapboxOverlay.isMajorRiverName(station.river) ||
              HydroRoMapboxOverlay.isDanubeName(station.name),
        )
        .toList(growable: false);
  }

  List<CommunityPost> get _visibleReports => filterFullMapReports(
    reports: _activeReports,
    center: _activeFilterCenter,
    radiusKm: _localRadiusKm,
    categories: _reportCategories,
  );

  List<CommunityPost> get _visibleCatches => filterFullMapCatches(
    catches: _publicCatches,
    center: _activeFilterCenter,
    radiusKm: _localRadiusKm,
  );

  Future<void> _locateUser({bool recenter = false}) async {
    if (_isLocating) return;

    setState(() => _isLocating = true);
    try {
      final languageCode = Localizations.localeOf(context).languageCode;
      final canonical = await ref
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: languageCode, force: recenter);
      if (!mounted) return;
      final deviceLocation = canonical.location;
      if (!canonical.hasUsableLocation || deviceLocation == null) {
        throw LocationFailure(_failureReasonFor(canonical.status));
      }
      final location = LatLng(
        deviceLocation.latitude,
        deviceLocation.longitude,
      );
      setState(() {
        _currentLocation = location;
        _locationUnavailableMessage = null;
      });
      await _syncUserAnnotation();
      await _syncStationAnnotations();
      await _syncReportAnnotations();
      await _syncCatchAnnotations();
      await _loadWaterAssetsForCenter(
        location,
        zoom: recenter ? 13.5 : 12.5,
        force: recenter,
      );
      if (recenter) {
        _clearSelectedStationFocus();
        _queueDeviceLocationCamera(location, zoom: 13.5);
      } else if (!_hasSelectedStationFocus &&
          _cameraCoordinator.activeTarget == null) {
        _queueDeviceLocationCamera(location, zoom: 12.5);
      }
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      final message = switch (failure.reason) {
        LocationFailureReason.serviceDisabled => context.l10n.locationRequired,
        LocationFailureReason.permissionDenied => context.l10n.locationRequired,
        LocationFailureReason.permissionDeniedForever =>
          context.l10n.locationRequired,
        LocationFailureReason.unavailable => context.l10n.notAvailable,
      };
      if (_cameraCoordinator.activeTarget == null) {
        setState(() => _locationUnavailableMessage = message);
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  LocationFailureReason _failureReasonFor(CurrentLocationStatus status) =>
      switch (status) {
        CurrentLocationStatus.serviceDisabled =>
          LocationFailureReason.serviceDisabled,
        CurrentLocationStatus.permissionDenied =>
          LocationFailureReason.permissionDenied,
        CurrentLocationStatus.permissionDeniedForever =>
          LocationFailureReason.permissionDeniedForever,
        _ => LocationFailureReason.unavailable,
      };

  void _clearSelectedStationFocus() {
    _hasSelectedStationFocus = false;
    if (!mounted) return;
    setState(() {
      _previewStation = null;
      _temporarilyHighlightedStation = null;
    });
    unawaited(_syncStationAnnotations());
    unawaited(_syncReportAnnotations());
  }

  void _queueDeviceLocationCamera(LatLng target, {required double zoom}) {
    final requestId = _cameraCoordinator.request(
      deviceLocationCameraTarget(
        latitude: target.latitude,
        longitude: target.longitude,
        zoom: zoom,
      ),
    );
    logMapRuntime(
      'map.device-location-queued',
      fields: {
        'cameraRequestId': requestId,
        'latitude': target.latitude,
        'longitude': target.longitude,
      },
    );
    unawaited(_applyPendingCameraIfReady());
  }

  Future<void> _applyPendingCameraIfReady() async {
    final mapboxMap = _mapboxMap;
    final application = _cameraCoordinator.takeReadyApplication();
    if (mapboxMap == null || application == null) return;
    final target = application.target;
    await mapboxMap.setCamera(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(target.longitude, target.latitude),
        ),
        zoom: target.zoom,
      ),
    );
    logMapRuntime(
      'map.camera-applied',
      fields: {
        'cameraRequestId': application.requestId,
        'source': target.source,
        'entityId': target.entityId,
        'latitude': target.latitude,
        'longitude': target.longitude,
        'replay': application.isReplay,
      },
    );
  }

  bool get _annotationSyncBlocked =>
      _isChangingMapStyle && !_isCompletingStyleChange;

  Future<void> _syncStationAnnotations() async {
    if (_annotationSyncBlocked) return;
    final manager = _stationAnnotationManager;
    final highlightManager = _stationHighlightAnnotationManager;
    if (!_cameraCoordinator.isReady ||
        manager == null ||
        highlightManager == null) {
      return;
    }

    final existingAnnotations = await manager.getAnnotations();
    final visibleStations = _visibleStations;
    if (!_stationLayerVisible) {
      if (existingAnnotations.isNotEmpty) {
        await manager.deleteAll();
      }
      _stationAnnotationFingerprint = null;
    } else {
      final fingerprint = _buildStationAnnotationFingerprint(visibleStations);
      final annotationsChanged =
          existingAnnotations.length != visibleStations.length ||
          _stationAnnotationFingerprint != fingerprint;
      if (annotationsChanged) {
        await manager.deleteAll();
        if (visibleStations.isNotEmpty) {
          final annotations = <mapbox.PointAnnotationOptions>[];
          for (final station in visibleStations) {
            final option = await _stationAnnotationOptions(station);
            if (option != null) annotations.add(option);
          }
          if (annotations.isNotEmpty) await manager.createMulti(annotations);
        }
        _stationAnnotationFingerprint = fingerprint;
      }
    }

    await highlightManager.deleteAll();
    final highlightedStation = _temporarilyHighlightedStation;
    final highlightedById = <String, Station>{
      if (_favoriteStationsVisible)
        for (final station in visibleStations)
          if (_favoriteStationIds.contains(station.id)) station.id: station,
    };
    if (highlightedStation != null) {
      highlightedById[highlightedStation.id] = highlightedStation;
    }
    if (highlightedById.isNotEmpty) {
      await highlightManager.createMulti(
        highlightedById.values
            .map(
              (station) => _stationHighlightOptions(
                station,
                highlighted: station.id == highlightedStation?.id,
                favorite: _favoriteStationIds.contains(station.id),
              ),
            )
            .toList(growable: false),
      );
    }
    logMapRuntime(
      'layers.station-annotations',
      fields: {
        'fetched': _stations.length,
        'visible': visibleStations.length,
        'created': _stationLayerVisible ? visibleStations.length : 0,
        'highlighted': highlightedById.length,
        'favoriteVisible': highlightedById.values
            .where((station) => _favoriteStationIds.contains(station.id))
            .length,
      },
    );
  }

  String _buildStationAnnotationFingerprint(Iterable<Station> source) {
    final stations = List<Station>.of(source)
      ..sort((left, right) => left.id.compareTo(right.id));

    return stations
        .map((station) {
          return '${station.id}|'
              '${station.latitude.toStringAsFixed(6)}|'
              '${station.longitude.toStringAsFixed(6)}|'
              '${station.hasKnownTrend ? 1 : 0}|'
              '${station.trend.name}|'
              '${_favoriteStationIds.contains(station.id)}|'
              '${_previewStation?.id == station.id}';
        })
        .join(';');
  }

  Future<mapbox.PointAnnotationOptions?> _stationAnnotationOptions(
    Station station,
  ) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !mounted) return null;
    final trend = station.hasKnownTrend ? station.trend.name : 'unknown';
    final imageId = 'fluviai-station-$trend-v1';
    if (!_registeredWaterAssetStyleImageIds.contains(imageId)) {
      try {
        final bytes = await FluviMapPinSystem.rasterize(
          MapFeatureRegistry.forStation(station, context.l10n),
          cacheKey: imageId,
          logicalSize: 42,
          pixelRatio: 2,
        );
        await mapboxMap.style.addStyleImage(
          imageId,
          2,
          mapbox.MbxImage(width: 100, height: 100, data: bytes),
          false,
          const [],
          const [],
          null,
        );
        _registeredWaterAssetStyleImageIds.add(imageId);
      } on Exception {
        return null;
      }
    }
    return mapbox.PointAnnotationOptions(
      geometry: mapbox.Point(
        coordinates: mapbox.Position(station.longitude, station.latitude),
      ),
      iconAnchor: mapbox.IconAnchor.BOTTOM,
      iconImage: imageId,
      iconSize: _previewStation?.id == station.id
          ? .98
          : _favoriteStationIds.contains(station.id)
          ? .88
          : .78,
      symbolSortKey: _previewStation?.id == station.id
          ? 0
          : _favoriteStationIds.contains(station.id)
          ? 4
          : station.hasKnownTrend
          ? 14
          : 22,
      customData: <String, Object>{
        'type': 'water_station',
        'stationId': station.id,
      },
    );
  }

  mapbox.CircleAnnotationOptions _stationHighlightOptions(
    Station station, {
    bool highlighted = false,
    bool favorite = false,
  }) {
    final stationColor = _stationTrendColor(station);
    final fillColor = highlighted
        ? fullMapTemporaryStationHighlightColor
        : favorite
        ? MapFeatureRegistry.favorite
        : station.hasKnownTrend
        ? stationColor
        : stationColor.withValues(alpha: .88);

    return mapbox.CircleAnnotationOptions(
      geometry: mapbox.Point(
        coordinates: mapbox.Position(station.longitude, station.latitude),
      ),
      circleRadius: highlighted ? 22 : 18,
      circleColor: _mapboxColor(fillColor.withValues(alpha: .18)),
      circleOpacity: 1,
      circleStrokeColor: _mapboxColor(
        highlighted || favorite ? Colors.white : const Color(0xFF06141D),
      ),
      circleStrokeWidth: highlighted ? 2.4 : 1.7,
      circleSortKey: highlighted
          ? 60
          : favorite
          ? 40
          : 20,
      customData: <String, Object>{
        'type': 'water_station',
        'stationId': station.id,
      },
    );
  }

  Color _stationTrendColor(Station station) {
    return MapFeatureRegistry.stationTrendColor(station);
  }

  Future<void> _syncUserAnnotation() async {
    if (_annotationSyncBlocked) return;
    final manager = _userAnnotationManager;
    final location = _currentLocation;
    if (!_cameraCoordinator.isReady || manager == null || location == null) {
      return;
    }

    await manager.deleteAll();
    await manager.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        ),
        circleRadius: 8,
        circleColor: _mapboxColor(MapFeatureRegistry.currentLocation),
        circleOpacity: .96,
        circleStrokeColor: _mapboxColor(Colors.white),
        circleStrokeWidth: 3,
        circleSortKey: 50,
        customData: const <String, Object>{'type': 'current_location'},
      ),
    );
  }

  void _handleStationAnnotationTap(mapbox.PointAnnotation annotation) {
    final stationId = annotation.customData?['stationId']?.toString();
    if (stationId == null) return;

    Station? station;
    for (final item in _stations) {
      if (item.id == stationId) {
        station = item;
        break;
      }
    }
    if (station == null || !mounted) return;

    ref.read(selectedContextProvider.notifier).publishStation(station);
    setState(() {
      _temporarilyHighlightedStation = station;
      _previewStation = station;
      _previewStationWaterResult = null;
      _previewWaterAsset = null;
      _previewWaterAssetDetail = null;
      _previewWaterAssetState = null;
      _previewHydropowerPin = null;
      _previewHydropowerState = null;
      _hydroPublicSelection = null;
      _previewRiver = null;
      _previewRiverDetail = null;
      _previewRiverState = null;
      _isLoadingHydroSelection = false;
      _isHydroPanelExpanded = false;
    });
    unawaited(_loadPreviewStationWater(station));
    unawaited(_syncStationAnnotations());
    unawaited(_syncReportAnnotations());
    unawaited(_syncCatchAnnotations());
    unawaited(_syncWaterAssetAnnotations());
    unawaited(_syncHydropowerAnnotations());
    unawaited(_applyHydroRuntime());
  }

  Future<void> _syncReportAnnotations() async {
    if (_annotationSyncBlocked) return;
    final manager = _reportAnnotationManager;
    if (!_cameraCoordinator.isReady || manager == null) return;
    await manager.deleteAll();
    final reports = _communityReportsVisible
        ? _visibleReports
        : const <CommunityPost>[];
    if (reports.isNotEmpty) {
      await manager.createMulti(
        reports
            .map((report) {
              final category = report.reportCategory ?? ReportCategory.other;
              final presentation = MapFeatureRegistry.forReportCategory(
                category,
                context.l10n,
              );
              return mapbox.CircleAnnotationOptions(
                geometry: mapbox.Point(
                  coordinates: mapbox.Position(
                    report.longitude!,
                    report.latitude!,
                  ),
                ),
                circleRadius: 7,
                circleColor: _mapboxColor(presentation.color),
                circleOpacity: .96,
                circleStrokeColor: _mapboxColor(Colors.white),
                circleStrokeWidth: 2.4,
                circleSortKey: 30,
                customData: <String, Object>{
                  'type': 'community_report',
                  'reportId': report.id,
                },
              );
            })
            .toList(growable: false),
      );
    }
    logMapRuntime(
      'layers.report-annotations',
      fields: {
        'fetched': _activeReports.length,
        'visible': reports.length,
        'created': reports.length,
      },
    );
  }

  void _handleReportAnnotationTap(mapbox.CircleAnnotation annotation) {
    final reportId = annotation.customData?['reportId']?.toString();
    if (reportId == null) return;
    CommunityPost? report;
    for (final item in _activeReports) {
      if (item.id == reportId) {
        report = item;
        break;
      }
    }
    if (report == null || !mounted) return;
    AppNavigator.open<void>(
      context,
      AppDestination.reportDetail,
      arguments: report,
    );
  }

  Future<void> _syncCatchAnnotations() async {
    if (_annotationSyncBlocked) return;
    final manager = _catchAnnotationManager;
    if (!_cameraCoordinator.isReady || manager == null) return;
    await manager.deleteAll();
    if (!mounted) return;
    final catches = _publicCatchesVisible
        ? _visibleCatches
        : const <CommunityPost>[];
    if (catches.isNotEmpty) {
      final presentation = MapFeatureRegistry.forFeature(
        MapFeatureType.catchEntry,
        context.l10n,
      );
      await manager.createMulti(
        catches
            .map(
              (catchPost) => mapbox.CircleAnnotationOptions(
                geometry: mapbox.Point(
                  coordinates: mapbox.Position(
                    catchPost.longitude!,
                    catchPost.latitude!,
                  ),
                ),
                circleRadius: 7,
                circleColor: _mapboxColor(presentation.color),
                circleOpacity: .96,
                circleStrokeColor: _mapboxColor(Colors.white),
                circleStrokeWidth: 2.4,
                circleSortKey: 28,
                customData: <String, Object>{
                  'type': 'public_catch',
                  'catchId': catchPost.id,
                },
              ),
            )
            .toList(growable: false),
      );
    }
    logMapRuntime(
      'layers.catch-annotations',
      fields: {
        'fetched': _publicCatches.length,
        'visible': catches.length,
        'created': catches.length,
      },
    );
  }

  void _handleCatchAnnotationTap(mapbox.CircleAnnotation annotation) {
    final catchId = annotation.customData?['catchId']?.toString();
    if (catchId == null) return;
    CommunityPost? catchPost;
    for (final item in _publicCatches) {
      if (item.id == catchId) {
        catchPost = item;
        break;
      }
    }
    if (catchPost == null || !mounted) return;
    AppNavigator.open<void>(
      context,
      AppDestination.catchDetail,
      arguments: catchPost,
    );
  }

  List<WaterAssetRef> get _visibleWaterAssets {
    if (!_hasPremiumWater ||
        !_effectiveHydroPreferences.enabled ||
        _cameraZoom < 7.8) {
      return const <WaterAssetRef>[];
    }
    final densityKeys = _visibleHydroDensityKeys;
    return _waterAssets
        .where((asset) {
          if (asset.type == WaterAssetType.dam && !_damLayerVisible) {
            return false;
          }
          if (asset.type == WaterAssetType.reservoir &&
              !_reservoirLayerVisible) {
            return false;
          }
          final key = '${asset.entityType}:${asset.id}';
          final priority =
              _previewWaterAsset?.id == asset.id ||
              _savedWaterAssetKeys.contains(key) ||
              asset.hasOperationalData ||
              asset.communityReportCount > 0;
          return priority && densityKeys.contains(key);
        })
        .toList(growable: false);
  }

  Set<String> get _visibleHydroDensityKeys {
    final selectedKeys = <String>{
      ..._savedWaterAssetKeys,
      if (_previewWaterAsset case final asset?)
        '${asset.entityType}:${asset.id}',
      if (_previewHydropowerPin case final plant?)
        'hydropower:${plant.entityId}',
    };
    final candidates = <HydroDensityCandidate>[
      for (final asset in _waterAssets)
        HydroDensityCandidate(
          key: '${asset.entityType}:${asset.id}',
          latitude: asset.latitude,
          longitude: asset.longitude,
          priority:
              (asset.hasOperationalData ? 420 : 0) +
              (_savedWaterAssetKeys.contains('${asset.entityType}:${asset.id}')
                  ? 260
                  : 0) +
              (asset.communityReportCount.clamp(0, 12) * 18) +
              (asset.type == WaterAssetType.reservoir ? 80 : 60),
        ),
      for (final plant in _hydropowerPins)
        HydroDensityCandidate(
          key: 'hydropower:${plant.entityId}',
          latitude: plant.latitude,
          longitude: plant.longitude,
          priority:
              plant.priority +
              (plant.hasOperationalData ? 440 : 0) +
              (_savedWaterAssetKeys.contains('hydropower:${plant.entityId}')
                  ? 260
                  : 0) +
              (plant.communityReportCount.clamp(0, 12) * 18) +
              70,
        ),
    ];
    return selectHydroDensityKeys(
      candidates: candidates,
      zoom: _cameraZoom,
      selectedKeys: selectedKeys,
    );
  }

  Future<void> _syncWaterAssetAnnotations() async {
    if (_annotationSyncBlocked) return;
    final manager = _waterAssetAnnotationManager;
    final haloManager = _waterAssetHaloAnnotationManager;
    final mapboxMap = _mapboxMap;
    if (!_cameraCoordinator.isReady ||
        manager == null ||
        haloManager == null ||
        mapboxMap == null) {
      return;
    }
    final assets = _visibleWaterAssets;
    final fingerprintEntries = assets.map((asset) {
      final key = '${asset.entityType}:${asset.id}';
      return '$key|${asset.stateTrend}|${asset.hasOperationalData}|'
          '${asset.communityReportCount}|'
          '${_savedWaterAssetKeys.contains(key)}|'
          '${_previewWaterAsset?.id == asset.id}';
    }).toList()..sort();
    final fingerprint = fingerprintEntries.join(';');
    if (_waterAssetAnnotationFingerprint == fingerprint) return;
    await manager.deleteAll();
    await haloManager.deleteAll();
    if (assets.isEmpty) {
      _waterAssetAnnotationFingerprint = fingerprint;
      return;
    }

    final haloOptions = <mapbox.CircleAnnotationOptions>[];
    final options = <mapbox.PointAnnotationOptions>[];
    for (final asset in assets) {
      if (!mounted) return;
      final presentation = MapFeatureRegistry.forFeature(
        asset.type == WaterAssetType.dam
            ? MapFeatureType.dam
            : MapFeatureType.reservoir,
        context.l10n,
      );
      final imageId = await _ensureWaterAssetStyleImage(
        mapboxMap,
        presentation,
        asset,
      );
      if (imageId == null) continue;
      final selected = _previewWaterAsset?.id == asset.id;
      final key = '${asset.entityType}:${asset.id}';
      final saved = _savedWaterAssetKeys.contains(key);
      if (selected ||
          saved ||
          asset.hasOperationalData ||
          asset.communityReportCount > 0) {
        final stateColor = saved
            ? MapFeatureRegistry.favorite
            : MapFeatureRegistry.waterStateColor(asset.stateTrend);
        haloOptions.add(
          mapbox.CircleAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(asset.longitude, asset.latitude),
            ),
            circleRadius: selected ? 24 : 20,
            circleColor: _mapboxColor(
              stateColor.withValues(alpha: selected ? .20 : .12),
            ),
            circleOpacity: 1,
            circleStrokeColor: _mapboxColor(
              selected ? Colors.white : stateColor.withValues(alpha: .72),
            ),
            circleStrokeWidth: selected ? 2.2 : 1.4,
            circleSortKey: selected ? 22 : 18,
          ),
        );
      }
      options.add(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(asset.longitude, asset.latitude),
          ),
          iconAnchor: mapbox.IconAnchor.BOTTOM,
          iconImage: imageId,
          iconSize: selected
              ? 1.04
              : asset.type == WaterAssetType.reservoir
              ? .72
              : .82,
          symbolSortKey: selected
              ? 0
              : saved
              ? 4
              : asset.hasOperationalData
              ? 8
              : asset.communityReportCount > 0
              ? 12
              : 24,
          customData: <String, Object>{
            'type': 'water_asset',
            'assetId': asset.id,
            'assetType': asset.entityType,
          },
        ),
      );
    }
    if (haloOptions.isNotEmpty) await haloManager.createMulti(haloOptions);
    if (options.isNotEmpty) await manager.createMulti(options);
    _waterAssetAnnotationFingerprint = fingerprint;
    logMapRuntime(
      'layers.water-asset-annotations',
      fields: {
        'fetched': _waterAssets.length,
        'visible': assets.length,
        'created': options.length,
        'halos': haloOptions.length,
        'damsVisible': _damLayerVisible,
        'reservoirsVisible': _reservoirLayerVisible,
      },
    );
  }

  List<WaterMapPin> get _visibleHydropowerPins {
    if (!_hasPremiumWater ||
        !_effectiveHydroPreferences.enabled ||
        _cameraZoom < 7.8 ||
        !_hydropowerLayerVisible) {
      return const <WaterMapPin>[];
    }
    final densityKeys = _visibleHydroDensityKeys;
    return _hydropowerPins
        .where((plant) {
          final key = 'hydropower:${plant.entityId}';
          final priority =
              _cameraZoom >= 10.8 ||
              _previewHydropowerPin?.entityId == plant.entityId ||
              _savedWaterAssetKeys.contains(key) ||
              plant.hasOperationalData ||
              plant.communityReportCount > 0 ||
              plant.priority >= 80;
          return priority && densityKeys.contains(key);
        })
        .toList(growable: false);
  }

  Color _hydropowerOperationColor(String operationState) =>
      switch (operationState) {
        'ACTIVE' => const Color(0xFF00E676),
        'INACTIVE' => const Color(0xFF78909C),
        'POSSIBLE_ACTIVE' => const Color(0xFFF59E0B),
        _ => const Color(0xFF78909C),
      };

  Future<void> _syncHydropowerAnnotations() async {
    if (_annotationSyncBlocked) return;
    final manager = _hydropowerAnnotationManager;
    final haloManager = _hydropowerHaloAnnotationManager;
    final mapboxMap = _mapboxMap;
    if (!_cameraCoordinator.isReady ||
        manager == null ||
        haloManager == null ||
        mapboxMap == null) {
      return;
    }
    final pins = _visibleHydropowerPins;
    final fingerprintEntries = pins.map((pin) {
      final key = 'hydropower:${pin.entityId}';
      return '$key|${pin.operationState}|${pin.hasOperationalData}|'
          '${pin.communityReportCount}|${pin.priority}|'
          '${_savedWaterAssetKeys.contains(key)}|'
          '${_previewHydropowerPin?.entityId == pin.entityId}';
    }).toList()..sort();
    final fingerprint = fingerprintEntries.join(';');
    if (_hydropowerAnnotationFingerprint == fingerprint) return;
    await manager.deleteAll();
    await haloManager.deleteAll();
    if (pins.isEmpty) {
      _hydropowerAnnotationFingerprint = fingerprint;
      return;
    }

    final haloOptions = <mapbox.CircleAnnotationOptions>[];
    final options = <mapbox.PointAnnotationOptions>[];
    for (final pin in pins) {
      if (!mounted) return;
      final presentation = MapFeatureRegistry.forFeature(
        MapFeatureType.hydropower,
        context.l10n,
      );
      final imageId = await _ensureHydropowerStyleImage(
        mapboxMap,
        presentation,
        pin,
      );
      if (imageId == null) continue;
      final selected = _previewHydropowerPin?.entityId == pin.entityId;
      final key = 'hydropower:${pin.entityId}';
      final saved = _savedWaterAssetKeys.contains(key);
      final operationColor = saved
          ? MapFeatureRegistry.favorite
          : _hydropowerOperationColor(pin.operationState);
      if (selected ||
          saved ||
          pin.operationState != 'UNKNOWN' ||
          pin.communityReportCount > 0) {
        haloOptions.add(
          mapbox.CircleAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(pin.longitude, pin.latitude),
            ),
            circleRadius: selected ? 24 : 19,
            circleColor: _mapboxColor(
              operationColor.withValues(alpha: selected ? .22 : .12),
            ),
            circleOpacity: 1,
            circleStrokeColor: _mapboxColor(
              selected ? Colors.white : operationColor.withValues(alpha: .78),
            ),
            circleStrokeWidth: selected ? 2.2 : 1.4,
            circleSortKey: selected ? 28 : 21,
          ),
        );
      }
      options.add(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(pin.longitude, pin.latitude),
          ),
          iconAnchor: mapbox.IconAnchor.BOTTOM,
          iconImage: imageId,
          iconSize: selected ? 1.04 : .82,
          symbolSortKey: selected
              ? 0
              : saved
              ? 4
              : pin.hasOperationalData
              ? 8
              : pin.communityReportCount > 0
              ? 12
              : 20 + (100 - pin.priority.clamp(0, 100)).toDouble(),
          customData: <String, Object>{
            'type': 'hydropower_plant',
            'plantId': pin.entityId,
          },
        ),
      );
    }
    if (haloOptions.isNotEmpty) await haloManager.createMulti(haloOptions);
    if (options.isNotEmpty) await manager.createMulti(options);
    _hydropowerAnnotationFingerprint = fingerprint;
    logMapRuntime(
      'layers.hydropower-annotations',
      fields: {
        'fetched': _hydropowerPins.length,
        'visible': pins.length,
        'created': options.length,
      },
    );
  }

  Future<String?> _ensureHydropowerStyleImage(
    mapbox.MapboxMap mapboxMap,
    MapFeaturePresentation presentation,
    WaterMapPin pin,
  ) async {
    final operation = pin.operationState.toLowerCase();
    final reportBadge = pin.communityReportCount.clamp(0, 9);
    final imageId = 'fluviai-hydropower-$operation-r$reportBadge-v1';
    if (_registeredWaterAssetStyleImageIds.contains(imageId)) return imageId;
    try {
      final bytes = await FluviMapPinSystem.rasterize(
        presentation,
        cacheKey: imageId,
        logicalSize: 42,
        pixelRatio: 2,
        badgeCount: pin.communityReportCount,
      );
      await mapboxMap.style.addStyleImage(
        imageId,
        2,
        mapbox.MbxImage(width: 100, height: 100, data: bytes),
        false,
        const [],
        const [],
        null,
      );
      _registeredWaterAssetStyleImageIds.add(imageId);
      return imageId;
    } on Exception {
      return null;
    }
  }

  void _handleHydropowerAnnotationTap(mapbox.PointAnnotation annotation) {
    final plantId = annotation.customData?['plantId']?.toString();
    if (plantId == null) return;
    WaterMapPin? selected;
    for (final pin in _hydropowerPins) {
      if (pin.entityId == plantId) {
        selected = pin;
        break;
      }
    }
    if (selected == null || !mounted) return;
    _publishHydropowerContext(selected);
    setState(() {
      _previewHydropowerPin = selected;
      _previewHydropowerState = null;
      _previewHydroDispatchSnapshot = null;
      _isLoadingHydroSelection = true;
      _previewWaterAsset = null;
      _previewStation = null;
      _temporarilyHighlightedStation = null;
      _hydroPublicSelection = null;
      _previewRiver = null;
      _previewRiverDetail = null;
      _previewRiverState = null;
      _isHydroPanelExpanded = false;
    });
    unawaited(_syncStationAnnotations());
    unawaited(_syncWaterAssetAnnotations());
    unawaited(_syncHydropowerAnnotations());
    unawaited(_refreshHydropowerPreview(selected));
    unawaited(_applyHydroRuntime());
  }

  void _publishHydropowerContext(WaterMapPin pin) {
    ref
        .read(selectedContextProvider.notifier)
        .select(SelectedContext.fromHydropowerPin(pin));
  }

  Future<void> _refreshHydropowerPreview(WaterMapPin pin) async {
    HydroMapDispatchSnapshot? snapshot;
    try {
      snapshot = await _hydroDispatchService.getMapDispatchSnapshot(
        pin.entityId,
      );
    } on Exception {
      // Forecast is optional. The canonical map pin remains independently valid.
    }
    if (!mounted || _previewHydropowerPin?.entityId != pin.entityId) return;
    setState(() {
      _previewHydroDispatchSnapshot = snapshot;
      _isLoadingHydroSelection = false;
    });
    ref
        .read(selectedContextProvider.notifier)
        .select(
          SelectedContext(
            countryCode: pin.countryCode,
            locationName: pin.name,
            latitude: pin.latitude,
            longitude: pin.longitude,
            waterId: pin.waterBodyId,
            waterName: pin.riverName,
            riverName: pin.riverName,
            damId: snapshot?.damId,
            reservoirId: snapshot?.reservoirId,
            hydropowerPlantId: pin.entityId,
            source: pin.stateSource,
            observedAt: snapshot?.updatedAt,
          ),
        );
  }

  Future<void> _toggleHydropowerFavorite(WaterMapPin pin) async {
    final key = 'hydropower:${pin.entityId}';
    final isSaved = _savedWaterAssetKeys.contains(key);
    try {
      if (isSaved) {
        await _savedItemsService.remove(
          type: 'hydropower',
          referenceId: pin.entityId,
        );
      } else {
        await _savedItemsService.save(
          type: 'hydropower',
          referenceId: pin.entityId,
          title: pin.name,
          subtitle: pin.riverName,
          latitude: pin.latitude,
          longitude: pin.longitude,
          metadata: <String, Object?>{
            'source': pin.stateSource,
            'water_body_id': pin.waterBodyId,
            'canonical_key': pin.canonicalKey,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        final next = <String>{..._savedWaterAssetKeys};
        isSaved ? next.remove(key) : next.add(key);
        _savedWaterAssetKeys = next;
      });
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apele mele nu sunt disponibile momentan.'),
        ),
      );
    }
  }

  Future<void> _openHydropowerDetails(WaterMapPin pin) async {
    if (_previewHydropowerState == null ||
        _previewHydropowerState?.plantId != pin.entityId) {
      await _refreshHydropowerPreview(pin);
    }
    if (!mounted) return;
    await AppNavigator.open<void>(
      context,
      AppDestination.hydropower,
      arguments: pin.name,
    );
  }

  Future<String?> _ensureWaterAssetStyleImage(
    mapbox.MapboxMap mapboxMap,
    MapFeaturePresentation presentation,
    WaterAssetRef asset,
  ) async {
    final trend = switch (asset.stateTrend) {
      'rising' => 'rising',
      'stable' => 'stable',
      'falling' => 'falling',
      _ => 'unknown',
    };
    final reportBadge = asset.communityReportCount.clamp(0, 9);
    final imageId = 'fluviai-water-${asset.entityType}-$trend-r$reportBadge-v2';
    if (_registeredWaterAssetStyleImageIds.contains(imageId)) return imageId;
    try {
      final bytes = await FluviMapPinSystem.rasterize(
        presentation,
        cacheKey: imageId,
        logicalSize: 42,
        pixelRatio: 2,
        badgeCount: asset.communityReportCount,
      );
      await mapboxMap.style.addStyleImage(
        imageId,
        2,
        mapbox.MbxImage(width: 100, height: 100, data: bytes),
        false,
        const [],
        const [],
        null,
      );
      _registeredWaterAssetStyleImageIds.add(imageId);
      return imageId;
    } on Exception {
      return null;
    }
  }

  void _handleWaterAssetAnnotationTap(mapbox.PointAnnotation annotation) {
    final assetId = annotation.customData?['assetId']?.toString();
    if (assetId == null) return;
    WaterAssetRef? selected;
    for (final asset in _waterAssets) {
      if (asset.id == assetId) {
        selected = asset;
        break;
      }
    }
    if (selected == null || !mounted) return;
    unawaited(_selectWaterAsset(selected));
  }

  Future<void> _selectWaterAsset(
    WaterAssetRef selected, {
    bool preservePublicSelection = false,
  }) async {
    ref
        .read(selectedContextProvider.notifier)
        .select(
          SelectedContext(
            countryCode: selected.countryCode,
            locationName: selected.name,
            latitude: selected.latitude,
            longitude: selected.longitude,
            waterId: selected.waterBodyId,
            waterName: selected.name,
            riverName: selected.riverName,
            damId: selected.type == WaterAssetType.dam ? selected.id : null,
            reservoirId: selected.type == WaterAssetType.reservoir
                ? selected.id
                : null,
            source: 'ANAR',
          ),
        );
    setState(() {
      _previewWaterAsset = selected;
      _previewWaterAssetDetail = null;
      _previewWaterAssetState = null;
      _previewHydropowerPin = null;
      _previewHydropowerState = null;
      _previewStation = null;
      _temporarilyHighlightedStation = null;
      _previewRiver = null;
      _previewRiverDetail = null;
      _previewRiverState = null;
      if (!preservePublicSelection) {
        _hydroPublicSelection = HydroPublicFeatureSelection(
          type: selected.type == WaterAssetType.reservoir
              ? HydroPublicFeatureType.reservoir
              : HydroPublicFeatureType.dam,
          displayName: selected.name,
          latitude: selected.latitude,
          longitude: selected.longitude,
        );
      }
      _isLoadingHydroSelection = true;
      _isHydroPanelExpanded = false;
    });
    unawaited(_syncStationAnnotations());
    unawaited(_syncWaterAssetAnnotations());
    unawaited(_syncHydropowerAnnotations());
    unawaited(_applyHydroRuntime());

    WaterAssetDetail? detail;
    WaterEntityState? state;
    try {
      detail = await _waterAssetService.getDetail(selected);
    } on Exception {
      // Static identity remains available without detail metrics.
    }
    try {
      state = await _waterAssetService.getState(selected);
    } on Exception {
      // UNKNOWN is intentionally preserved.
    }
    if (!mounted || _previewWaterAsset?.id != selected.id) return;
    setState(() {
      _previewWaterAssetDetail = detail;
      _previewWaterAssetState = state;
      _isLoadingHydroSelection = false;
    });
  }

  Future<void> _toggleWaterAssetFavorite(WaterAssetRef asset) async {
    final key = '${asset.entityType}:${asset.id}';
    final isSaved = _savedWaterAssetKeys.contains(key);
    try {
      if (isSaved) {
        await _savedItemsService.remove(
          type: asset.entityType,
          referenceId: asset.id,
        );
      } else {
        await _savedItemsService.save(
          type: asset.entityType,
          referenceId: asset.id,
          title: asset.name,
          subtitle: [
            if (asset.riverName?.isNotEmpty == true) asset.riverName!,
            if (asset.county?.isNotEmpty == true) asset.county!,
          ].join(' · '),
          latitude: asset.latitude,
          longitude: asset.longitude,
          metadata: <String, Object?>{
            'source': 'ANAR',
            'basin_name': asset.basinName,
            'water_body_id': asset.waterBodyId,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        final next = <String>{..._savedWaterAssetKeys};
        isSaved ? next.remove(key) : next.add(key);
        _savedWaterAssetKeys = next;
      });
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apele mele nu sunt disponibile momentan.'),
        ),
      );
    }
  }

  Future<void> _openWaterAsset(WaterAssetRef asset) => AppNavigator.open<void>(
    context,
    AppDestination.reservoir,
    arguments: asset,
  );

  // Retained for the legacy filter sheet fallback while RC2 uses the compact
  // Hydro layer controller.
  // ignore: unused_element
  Future<void> _showUnavailableMapLayer(String label) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(label),
      content: Text(
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro'
            ? 'Acest strat nu este conectat la o sursă de date de producție.'
            : 'This layer is not connected to a production data source.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<void> _openStation(Station station) async {
    ProviderScope.containerOf(
      context,
    ).read(selectedContextProvider.notifier).selectStation(station);
    await AppNavigator.open<void>(
      context,
      AppDestination.station,
      arguments: station,
    );
  }

  Future<void> _openSearch() =>
      AppNavigator.open<void>(context, AppDestination.search);

  bool get _canChangeMapStyle =>
      _cameraCoordinator.isReady &&
      _hasLoadedInitialStyle &&
      !_isChangingMapStyle &&
      _mapboxMap != null &&
      _stationAnnotationManager != null &&
      _stationHighlightAnnotationManager != null &&
      _userAnnotationManager != null &&
      _reportAnnotationManager != null &&
      _catchAnnotationManager != null &&
      _waterAssetAnnotationManager != null &&
      _hydropowerAnnotationManager != null;

  Future<void> _openMapStyleSelector() async {
    if (!_canChangeMapStyle) return;
    final languageCode = Localizations.localeOf(context).languageCode;
    final sheetWidth = MediaQuery.sizeOf(
      context,
    ).width.clamp(0.0, 440.0).toDouble();
    final selectedStyle = await showModalBottomSheet<_FullMapStyle>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .58),
      constraints: BoxConstraints.tightFor(width: sheetWidth),
      builder: (context) => _MapStyleSelector(
        selectedStyle: _selectedMapStyle,
        languageCode: languageCode,
      ),
    );

    if (selectedStyle == null || !mounted) return;
    await _changeMapStyle(selectedStyle);
  }

  Future<void> _openHydroLayerControls() async {
    final result = await showModalBottomSheet<_HydroLayerSelection>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .62),
      builder: (sheetContext) => _HydroLayerSheet(
        initialStyle: _selectedMapStyle,
        initialPreferences: _hydroPreferences,
        stationLayerVisible: _stationLayerVisible,
        hydropowerLayerVisible: _hydropowerLayerVisible,
        hasPremium: _hasPremiumWater,
      ),
    );
    if (!mounted || result == null) return;
    if (result.requestUpgrade) {
      await AppNavigator.open<void>(context, AppDestination.premium);
      return;
    }
    setState(() {
      _hydroPreferences = result.preferences;
      _stationLayerVisible = result.stationLayerVisible;
      _damLayerVisible = result.preferences.dams;
      _reservoirLayerVisible = result.preferences.reservoirs;
      _hydropowerLayerVisible = result.hydropowerLayerVisible;
    });
    if (result.preferences.enabled && _hasPremiumWater) {
      await ref
          .read(contentRegionProvider.notifier)
          .selectCountry(countryCode: 'RO', region: 'România');
    }
    if (result.style != _selectedMapStyle) {
      await _changeMapStyle(result.style);
    } else {
      await _applyHydroRuntime();
      await _syncStationAnnotations();
      await _syncWaterAssetAnnotations();
      await _syncHydropowerAnnotations();
    }
    if (result.exploreRomania && mounted) await _exploreHydroRomania();
  }

  Future<void> _toggleHydroFromMap() async {
    if (!_hasPremiumWater) {
      await AppNavigator.open<void>(context, AppDestination.premium);
      return;
    }
    final enabled = !_hydroPreferences.enabled;
    setState(
      () => _hydroPreferences = _hydroPreferences.copyWith(enabled: enabled),
    );
    if (enabled) {
      await ref
          .read(contentRegionProvider.notifier)
          .selectCountry(countryCode: 'RO', region: 'România');
    } else {
      setState(() {
        _hydroPublicSelection = null;
        _previewRiver = null;
        _previewRiverDetail = null;
        _previewRiverState = null;
      });
    }
    await _applyHydroRuntime();
    await _refreshWaterAssetsAtCamera(force: true);
  }

  Future<void> _exploreHydroRomania() async {
    if (!_hasPremiumWater) {
      await AppNavigator.open<void>(context, AppDestination.premium);
      return;
    }
    setState(
      () => _hydroPreferences = _hydroPreferences.copyWith(enabled: true),
    );
    await ref
        .read(contentRegionProvider.notifier)
        .selectCountry(countryCode: 'RO', region: 'România');
    _cameraCoordinator.request(
      const RuntimeMapCameraTarget(
        source: 'hydro-ro-control',
        entityId: 'country-pack-ro',
        latitude: 45.9432,
        longitude: 24.9668,
        zoom: 5.65,
      ),
    );
    await _applyHydroRuntime();
    final mapboxMap = _mapboxMap;
    if (mapboxMap != null && _cameraCoordinator.isReady) {
      // This is an explicit user action on the already-mounted canonical map.
      // Apply it directly so a concurrent style-ready replay cannot consume the
      // coordinator request without producing the visible national overview.
      await mapboxMap.easeTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(24.9668, 45.9432)),
          zoom: 5.65,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(duration: 720),
      );
    } else {
      await _applyPendingCameraIfReady();
    }
  }

  // Legacy comprehensive community filter sheet; kept to preserve harvested
  // behavior until its non-Hydro controls move into the canonical controller.
  // ignore: unused_element
  Future<void> _openFilters() async {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final hasPremiumWater = _hasPremiumWater;
    var draft = _FullMapFilterSelection(
      stationLayerVisible: _stationLayerVisible,
      communityReportsVisible: _communityReportsVisible,
      favoriteStationsVisible: _favoriteStationsVisible,
      damLayerVisible: hasPremiumWater && _damLayerVisible,
      reservoirLayerVisible: hasPremiumWater && _reservoirLayerVisible,
      hydropowerLayerVisible: hasPremiumWater && _hydropowerLayerVisible,
      radiusKm: _localRadiusKm,
      reportCategories: _reportCategories,
    );
    final result = await showModalBottomSheet<Object>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101720),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => FractionallySizedBox(
          heightFactor: .86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  isRo ? 'Filtre hartă' : 'Map filters',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('full-map-approved-filters'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                  children: [
                    SwitchListTile.adaptive(
                      key: const ValueKey('full-map-filter-stations'),
                      secondary: const Icon(Icons.water_drop_rounded),
                      title: Text(
                        isRo ? 'Stații de monitorizare' : 'Monitoring stations',
                      ),
                      value: draft.stationLayerVisible,
                      onChanged: (value) => setSheetState(
                        () =>
                            draft = draft.copyWith(stationLayerVisible: value),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('full-map-filter-dams'),
                      secondary: const Icon(Icons.account_balance_rounded),
                      title: Text(isRo ? 'Baraje' : 'Dams'),
                      subtitle: hasPremiumWater
                          ? null
                          : Text(
                              isRo ? 'Disponibil în Pro' : 'Available in Pro',
                            ),
                      value: draft.damLayerVisible,
                      onChanged: !hasPremiumWater
                          ? null
                          : (value) => setSheetState(
                              () => draft = draft.copyWith(
                                damLayerVisible: value,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('full-map-filter-reservoirs'),
                      secondary: const Icon(Icons.water_rounded),
                      title: Text(isRo ? 'Lacuri de acumulare' : 'Reservoirs'),
                      subtitle: hasPremiumWater
                          ? null
                          : Text(
                              isRo ? 'Disponibil în Pro' : 'Available in Pro',
                            ),
                      value: draft.reservoirLayerVisible,
                      onChanged: !hasPremiumWater
                          ? null
                          : (value) => setSheetState(
                              () => draft = draft.copyWith(
                                reservoirLayerVisible: value,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('full-map-filter-hydropower'),
                      secondary: const Icon(Icons.bolt_rounded),
                      title: Text(isRo ? 'Hidrocentrale' : 'Hydropower'),
                      subtitle: hasPremiumWater
                          ? null
                          : Text(
                              isRo ? 'Disponibil în Pro' : 'Available in Pro',
                            ),
                      value: draft.hydropowerLayerVisible,
                      onChanged: !hasPremiumWater
                          ? null
                          : (value) => setSheetState(
                              () => draft = draft.copyWith(
                                hydropowerLayerVisible: value,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('full-map-filter-reports'),
                      secondary: const Icon(Icons.campaign_rounded),
                      title: Text(
                        isRo ? 'Rapoarte comunitare' : 'Community reports',
                      ),
                      value: draft.communityReportsVisible,
                      onChanged: (value) => setSheetState(
                        () => draft = draft.copyWith(
                          communityReportsVisible: value,
                        ),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      key: const ValueKey('full-map-filter-favorites'),
                      secondary: const Icon(Icons.bookmark_rounded),
                      title: Text(
                        isRo ? 'Stații favorite' : 'Favorite stations',
                      ),
                      subtitle: !_favoriteStationsService.isAuthenticated
                          ? Text(
                              isRo
                                  ? 'Autentificarea este necesară.'
                                  : 'Sign-in is required.',
                            )
                          : null,
                      value: draft.favoriteStationsVisible,
                      onChanged: !_favoriteStationsService.isAuthenticated
                          ? null
                          : (value) => setSheetState(
                              () => draft = draft.copyWith(
                                favoriteStationsVisible: value,
                              ),
                            ),
                    ),
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonFormField<double>(
                        key: const ValueKey('full-map-filter-radius'),
                        initialValue: draft.radiusKm,
                        dropdownColor: const Color(0xFF101720),
                        decoration: InputDecoration(
                          labelText: isRo ? 'Rază locală' : 'Local radius',
                        ),
                        items: [
                          for (final radius in const [10.0, 25.0, 50.0, 100.0])
                            DropdownMenuItem(
                              value: radius,
                              child: Text('${radius.toInt()} km'),
                            ),
                          DropdownMenuItem(
                            value: double.infinity,
                            child: Text(isRo ? 'Toată harta' : 'Entire map'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(
                            () => draft = draft.copyWith(radiusKm: value),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        isRo
                            ? 'Categorii rapoarte comunitare'
                            : 'Community report categories',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          FilterChip(
                            key: const ValueKey('full-map-filter-all-reports'),
                            label: Text(isRo ? 'Toate' : 'All'),
                            selected: draft.reportCategories.isEmpty,
                            onSelected: (_) => setSheetState(
                              () => draft = draft.copyWith(
                                reportCategories: const {},
                              ),
                            ),
                          ),
                          for (final category in ReportCategory.values)
                            FilterChip(
                              key: ValueKey(
                                'full-map-filter-report-${category.name}',
                              ),
                              label: Text(
                                MapFeatureRegistry.forReportCategory(
                                  category,
                                  context.l10n,
                                ).label,
                              ),
                              selected: draft.reportCategories.contains(
                                category,
                              ),
                              onSelected: (selected) => setSheetState(() {
                                final categories = <ReportCategory>{
                                  ...draft.reportCategories,
                                };
                                if (selected) {
                                  categories.add(category);
                                } else {
                                  categories.remove(category);
                                }
                                draft = draft.copyWith(
                                  reportCategories: categories,
                                );
                              }),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 28),
                    ListTile(
                      key: const ValueKey('full-map-filter-style'),
                      leading: const Icon(Icons.layers_rounded),
                      title: Text(
                        isRo ? 'Stil și strat de bază' : 'Style & base layer',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(_MapFilterAction.style),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      TextButton(
                        key: const ValueKey('full-map-filter-reset'),
                        onPressed: () => setSheetState(
                          () => draft = const _FullMapFilterSelection(),
                        ),
                        child: Text(isRo ? 'Resetează' : 'Reset'),
                      ),
                      const Spacer(),
                      FilledButton(
                        key: const ValueKey('full-map-filter-apply'),
                        onPressed: () => Navigator.of(sheetContext).pop(draft),
                        child: Text(isRo ? 'Aplică' : 'Apply'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == _MapFilterAction.style) {
      await _openMapStyleSelector();
      return;
    }
    if (result case final _FullMapFilterSelection selection) {
      setState(() {
        _stationLayerVisible = selection.stationLayerVisible;
        _communityReportsVisible = selection.communityReportsVisible;
        _favoriteStationsVisible = selection.favoriteStationsVisible;
        _damLayerVisible = selection.damLayerVisible;
        _reservoirLayerVisible = selection.reservoirLayerVisible;
        _hydropowerLayerVisible = selection.hydropowerLayerVisible;
        _localRadiusKm = selection.radiusKm;
        _reportCategories = selection.reportCategories;
      });
      await _syncStationAnnotations();
      await _syncReportAnnotations();
      await _syncCatchAnnotations();
      await _syncWaterAssetAnnotations();
      await _syncHydropowerAnnotations();
      await _refreshWaterAssetsAtCamera(force: true);
    }
  }

  Future<void> _changeMapStyle(
    _FullMapStyle style, {
    bool force = false,
  }) async {
    final mapboxMap = _mapboxMap;
    if (!_canChangeMapStyle || mapboxMap == null) return;
    if (!force && style == _selectedMapStyle) return;
    final styleUri = style.uri;

    setState(() {
      _isChangingMapStyle = true;
      _pendingMapStyle = style;
    });
    _cameraCoordinator.markStyleLoading();

    try {
      _cameraBeforeStyleChange = await mapboxMap.getCameraState();
      await mapboxMap.loadStyleURI(styleUri);
    } catch (_) {
      _cameraCoordinator.markStyleLoaded();
      unawaited(_applyPendingCameraIfReady());
      if (!mounted) {
        _finishStyleChange();
        return;
      }
      setState(_finishStyleChange);
      _showStyleChangeError();
    }
  }

  void _showStyleChangeError() {
    if (!mounted) return;
    final isRomanian = Localizations.localeOf(context).languageCode == 'ro';
    final message = isRomanian
        ? 'Stilul hărții nu a putut fi schimbat.'
        : 'The map style could not be changed.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  HydroIntelligenceViewData? _hydroPanelData() {
    final l10n = context.l10n;
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final station = _previewStation;
    if (station != null) {
      final waterResult = _previewStationWaterResult;
      final resultReading = waterResult?.latestReading;
      final currentReading = resultReading?.stationId == station.id
          ? resultReading
          : null;
      final hasCurrentLevel = currentReading != null || station.hasWaterLevel;
      final currentLevel = currentReading?.value ?? station.level;
      final currentUnit = currentReading?.unit ?? station.waterLevelUnit;
      final currentTemperature =
          currentReading?.waterTemperatureC ?? station.waterTemperatureC;
      final delta24h = realWaterIntervalDelta(
        waterResult?.history ?? const <WaterLevel>[],
        const Duration(hours: 24),
        stationId: station.id,
      );
      final delta24hLabel = delta24h == null
          ? (isRomanian
                ? 'Variația 24h indisponibilă'
                : '24h change unavailable')
          : '${_formatSignedMetric(delta24h.deltaCm)} ${delta24h.to.unit} / 24h'
                ' · ${_localizedTrend(delta24h.trend.name)}';
      final data = <HydroIntelligenceDatum>[
        if (station.river.isNotEmpty)
          HydroIntelligenceDatum(
            label: l10n.hydroRiver,
            value: station.river,
            icon: Icons.waves_rounded,
          ),
        if (hasCurrentLevel)
          HydroIntelligenceDatum(
            label: l10n.hydroLevel,
            value: '${_formatMetricValue(currentLevel)} $currentUnit',
            icon: Icons.water_drop_rounded,
          ),
        HydroIntelligenceDatum(
          label: l10n.hydroDelta24h,
          value: delta24hLabel,
          icon: Icons.swap_vert_rounded,
        ),
        if (currentTemperature case final temperature?)
          HydroIntelligenceDatum(
            label: isRomanian ? 'Temperatura apei' : 'Water temperature',
            value: '${_formatMetricValue(temperature)} °C',
            icon: Icons.thermostat_rounded,
          ),
      ];
      return HydroIntelligenceViewData(
        name: station.name,
        typeLabel: l10n.hydroStation,
        contextLabel: station.river.isEmpty ? null : station.river,
        icon: Icons.speed_rounded,
        accentColor: const Color(0xFF57E6B4),
        statusTitle: delta24hLabel,
        unavailableLabel: l10n.hydroOperationalUnavailable,
        statusLabel: hasCurrentLevel
            ? '${_formatMetricValue(currentLevel)} $currentUnit'
            : station.hasKnownTrend
            ? _localizedTrend(station.trend.name)
            : l10n.hydroEvidenceUnknown,
        hasOperationalStatus: station.hasKnownTrend || hasCurrentLevel,
        statusColor: _stationTrendColor(station),
        evidenceLabel: hasCurrentLevel
            ? _evidenceExplanation('MEASURED')
            : _evidenceExplanation('UNKNOWN'),
        sourceLabel: hasCurrentLevel
            ? _humanSourceLabel(
                currentReading?.sourceName ??
                    waterResult?.sourceName ??
                    station.waterLevelSource,
              )
            : null,
        freshnessLabel: hasCurrentLevel
            ? _hydroFreshnessLabel(
                currentReading?.effectiveFreshnessTimestamp ??
                    waterResult?.effectiveFreshnessTimestamp ??
                    station.waterFreshnessTimestamp ??
                    station.lastUpdate,
              )
            : null,
        unknownMessage: l10n.hydroUnknownState,
        relationships: station.river.isEmpty
            ? const <HydroRelationshipItem>[]
            : <HydroRelationshipItem>[
                HydroRelationshipItem(
                  label: isRomanian ? 'Pe apă' : 'On water',
                  title: station.river,
                  typeLabel: l10n.hydroRiver,
                  icon: Icons.waves_rounded,
                ),
              ],
        data: data,
      );
    }

    final asset = _previewWaterAsset;
    if (asset != null) {
      final detail = _previewWaterAssetDetail;
      final state = _previewWaterAssetState;
      final verifiedMetrics = detail?.metrics
          .where(
            (metric) =>
                metric.value != null &&
                metric.availabilityStatus?.toLowerCase() == 'available',
          )
          .toList(growable: false);
      if (asset.type == WaterAssetType.reservoir) {
        verifiedMetrics?.sort(
          (left, right) => _hydroMetricPriority(
            left.code,
          ).compareTo(_hydroMetricPriority(right.code)),
        );
      }
      DateTime? latestObservation;
      for (final metric
          in verifiedMetrics ?? const <WaterOperationalMetric>[]) {
        final observedAt = metric.observedAt;
        if (observedAt != null &&
            (latestObservation == null ||
                observedAt.isAfter(latestObservation))) {
          latestObservation = observedAt;
        }
      }
      final stateTrend =
          state?.officialTrend != null &&
              state!.officialTrend.toLowerCase() != 'unknown'
          ? state.officialTrend
          : _isOfficialOrAnalyticalEvidence(asset.stateSource)
          ? asset.stateTrend
          : 'unknown';
      final hasOperationalStatus =
          stateTrend.toLowerCase() != 'unknown' ||
          (_isOfficialOrAnalyticalEvidence(state?.source) &&
              state?.operationSignal.toLowerCase() != 'unknown' &&
              state?.operationSignal.isNotEmpty == true) ||
          verifiedMetrics?.isNotEmpty == true;
      final data = <HydroIntelligenceDatum>[
        for (final metric
            in verifiedMetrics?.take(3) ?? const <WaterOperationalMetric>[])
          HydroIntelligenceDatum(
            label: _hydroMetricLabel(metric),
            value: '${_formatMetricValue(metric.value!)} ${metric.unit ?? ''}'
                .trim(),
            icon: Icons.analytics_outlined,
          ),
        if (asset.riverName?.isNotEmpty == true)
          HydroIntelligenceDatum(
            label: l10n.hydroRiver,
            value: asset.riverName!,
            icon: Icons.waves_rounded,
          ),
      ];
      final source = state?.source ?? asset.stateSource;
      final isReservoir = asset.type == WaterAssetType.reservoir;
      return HydroIntelligenceViewData(
        name: asset.name,
        typeLabel: asset.type == WaterAssetType.dam
            ? l10n.hydroDam
            : l10n.hydroReservoir,
        contextLabel: asset.riverName,
        metadataLabel:
            asset.basinName?.isNotEmpty == true &&
                asset.basinName != asset.riverName
            ? asset.basinName
            : null,
        icon: asset.type == WaterAssetType.dam
            ? Icons.account_balance_rounded
            : Icons.water_rounded,
        accentColor: asset.type == WaterAssetType.dam
            ? MapFeatureRegistry.dam
            : MapFeatureRegistry.reservoir,
        statusTitle: isReservoir
            ? (isRomanian ? 'Date hidrologice' : 'Hydrological data')
            : l10n.hydroOperationalStatus,
        unavailableLabel: isReservoir
            ? (isRomanian
                  ? 'Date hidrologice indisponibile'
                  : 'Hydrological data unavailable')
            : l10n.hydroOperationalUnavailable,
        statusLabel: !hasOperationalStatus
            ? l10n.hydroEvidenceUnknown
            : stateTrend.toLowerCase() != 'unknown'
            ? _localizedTrend(stateTrend)
            : isReservoir
            ? (isRomanian
                  ? 'Date hidrologice disponibile'
                  : 'Hydrological data available')
            : l10n.hydroDataAvailable,
        hasOperationalStatus: hasOperationalStatus,
        statusColor: MapFeatureRegistry.waterStateColor(stateTrend),
        evidenceLabel: verifiedMetrics?.isNotEmpty == true
            ? _evidenceExplanation('MEASURED')
            : isReservoir
            ? null
            : hasOperationalStatus
            ? (isRomanian ? 'Stare documentată' : 'Documented status')
            : _evidenceExplanation('UNKNOWN'),
        sourceLabel: _humanSourceLabel(detail?.source ?? source),
        freshnessLabel: latestObservation == null
            ? null
            : _hydroFreshnessLabel(latestObservation),
        confidenceLabel: (state?.confidence ?? asset.stateConfidence) > 0
            ? _confidenceExplanation(state?.confidence ?? asset.stateConfidence)
            : null,
        relationships: _assetRelationships(asset, detail),
        unknownMessage: l10n.hydroUnknownState,
        data: data,
        loading: _isLoadingHydroSelection,
      );
    }

    final plant = _previewHydropowerPin;
    if (plant != null) {
      final state = _previewHydropowerState;
      final operation = state?.operationState ?? plant.operationState;
      final evidenceClass = state?.evidenceClass ?? plant.evidenceClass;
      final dispatch = _previewHydroDispatchSnapshot;
      final dispatchPresentation = HydroDispatchPresentation.mapSnapshot(
        dispatch,
        isRomanian: isRomanian,
      );
      final hasDispatchForecast = dispatch?.isAvailable == true;
      final hasOperationalEvidence =
          state?.evidenceValue != null ||
          (evidenceClass.isNotEmpty &&
              evidenceClass.toUpperCase() != 'UNKNOWN');
      final hasOperationalStatus =
          hasOperationalEvidence && operation.toUpperCase() != 'UNKNOWN';
      final data = <HydroIntelligenceDatum>[
        if (plant.riverName?.isNotEmpty == true)
          HydroIntelligenceDatum(
            label: l10n.hydroRiver,
            value: plant.riverName!,
            icon: Icons.waves_rounded,
          ),
        if (state?.operatorName?.isNotEmpty == true)
          HydroIntelligenceDatum(
            label: isRomanian ? 'Operator' : 'Operator',
            value: state!.operatorName!,
            icon: Icons.factory_outlined,
          ),
        if (state?.evidenceValue case final value?)
          HydroIntelligenceDatum(
            label: state?.evidenceMetric ?? l10n.hydroOfficialState,
            value: '${_formatMetricValue(value)} ${state?.evidenceUnit ?? ''}'
                .trim(),
            icon: Icons.verified_outlined,
          ),
      ];
      return HydroIntelligenceViewData(
        name: plant.name,
        typeLabel: l10n.hydroPlant,
        contextLabel: plant.riverName,
        icon: Icons.bolt_rounded,
        accentColor: MapFeatureRegistry.hydropower,
        forecastProbabilityLabel: hasDispatchForecast
            ? dispatchPresentation.probabilityLabel
            : null,
        forecastWindowLabel: hasDispatchForecast
            ? dispatchPresentation.windowLabel
            : null,
        forecastConfidenceLabel: hasDispatchForecast
            ? dispatchPresentation.confidenceLabel
            : null,
        forecastEvidenceLabel: hasDispatchForecast
            ? dispatchPresentation.evidenceLabel
            : null,
        statusTitle: isRomanian ? 'Stare de funcționare' : 'Operating status',
        unavailableLabel: l10n.hydroEvidenceUnknown,
        statusLabel: hasOperationalStatus
            ? _localizedOperation(operation)
            : l10n.hydroEvidenceUnknown,
        hasOperationalStatus: hasOperationalStatus,
        statusColor: _hydropowerOperationColor(operation),
        evidenceLabel: hasOperationalEvidence
            ? _evidenceExplanation(evidenceClass)
            : _evidenceExplanation('UNKNOWN'),
        sourceLabel: hasOperationalEvidence
            ? _humanSourceLabel(state?.evidenceSource ?? plant.stateSource)
            : null,
        freshnessLabel:
            !hasOperationalEvidence || state?.evidenceObservedAt == null
            ? null
            : _hydroFreshnessLabel(state?.evidenceObservedAt),
        confidenceLabel:
            hasOperationalEvidence &&
                (state?.confidence ?? plant.confidence) > 0
            ? _confidenceExplanation(state?.confidence ?? plant.confidence)
            : null,
        relationships: _hydropowerRelationships(plant, state),
        unknownMessage: l10n.hydroUnknownState,
        data: data,
        loading: _isLoadingHydroSelection,
      );
    }

    final selection = _hydroPublicSelection;
    if (selection == null) return null;
    final river = _previewRiver;
    final detail = _previewRiverDetail;
    final state = _previewRiverState;
    final data = <HydroIntelligenceDatum>[
      if (state != null && state.officialTrend != 'unknown')
        HydroIntelligenceDatum(
          label: l10n.hydroOfficialState,
          value: _localizedTrend(state.officialTrend),
          icon: Icons.trending_up_rounded,
        ),
      if (state != null && state.hasCommunityEvidence)
        HydroIntelligenceDatum(
          label: l10n.hydroCommunityState,
          value: state.communityEvidenceCount.toString(),
          icon: Icons.groups_outlined,
        ),
    ];
    final typeLabel = switch (selection.type) {
      HydroPublicFeatureType.river => l10n.hydroRiver,
      HydroPublicFeatureType.reservoir => l10n.hydroReservoir,
      HydroPublicFeatureType.dam => l10n.hydroDam,
    };
    final color = switch (selection.type) {
      HydroPublicFeatureType.river => const Color(0xFF37E4F2),
      HydroPublicFeatureType.reservoir => MapFeatureRegistry.reservoir,
      HydroPublicFeatureType.dam => MapFeatureRegistry.dam,
    };
    final isRiverSelection = selection.type == HydroPublicFeatureType.river;
    final isReservoirSelection =
        selection.type == HydroPublicFeatureType.reservoir;
    return HydroIntelligenceViewData(
      name: river?.name ?? selection.displayName,
      typeLabel: typeLabel,
      metadataLabel: river?.basinNames.firstOrNull,
      icon: switch (selection.type) {
        HydroPublicFeatureType.river => Icons.waves_rounded,
        HydroPublicFeatureType.reservoir => Icons.water_rounded,
        HydroPublicFeatureType.dam => Icons.account_balance_rounded,
      },
      accentColor: color,
      statusTitle: isRiverSelection || isReservoirSelection
          ? (isRomanian ? 'Date hidrologice' : 'Hydrological data')
          : l10n.hydroOperationalStatus,
      unavailableLabel: isRiverSelection
          ? (isRomanian
                ? 'Date curente indisponibile'
                : 'Current data unavailable')
          : isReservoirSelection
          ? (isRomanian
                ? 'Date hidrologice indisponibile'
                : 'Hydrological data unavailable')
          : l10n.hydroOperationalUnavailable,
      statusLabel: state == null || state.officialTrend == 'unknown'
          ? l10n.hydroEvidenceUnknown
          : _localizedTrend(state.officialTrend),
      hasOperationalStatus: state != null && state.officialTrend != 'unknown',
      evidenceLabel: isRiverSelection
          ? state?.hasCommunityEvidence == true
                ? _evidenceExplanation('COMMUNITY')
                : null
          : isReservoirSelection
          ? null
          : _evidenceExplanation('UNKNOWN'),
      sourceLabel: _humanSourceLabel(
        river?.provenanceSource ?? l10n.hydroMapPublicGeometry,
      ),
      freshnessLabel: null,
      confidenceLabel: state != null && state.confidence > 0
          ? _confidenceExplanation(state.confidence)
          : null,
      relationships: _riverRelationships(detail),
      unknownMessage: river == null
          ? l10n.hydroSelectedPublicOnly
          : l10n.hydroUnknownState,
      data: data,
      loading: _isLoadingHydroSelection,
    );
  }

  List<HydroRelationshipItem> _assetRelationships(
    WaterAssetRef asset,
    WaterAssetDetail? detail,
  ) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final relationships = <HydroRelationshipItem>[];
    if (asset.riverName?.isNotEmpty == true) {
      relationships.add(
        HydroRelationshipItem(
          label: isRomanian ? 'Pe apă' : 'On water',
          title: asset.riverName!,
          typeLabel: context.l10n.hydroRiver,
          icon: Icons.waves_rounded,
        ),
      );
    }
    final linkedNames = <String>{};
    for (final linked
        in detail?.linkedAssets ?? const <Map<String, dynamic>>[]) {
      final name =
          <Object?>[
                linked['name'],
                linked['asset_name'],
                linked['reservoir_name'],
                linked['dam_name'],
              ]
              .map((value) => value?.toString().trim())
              .whereType<String>()
              .where((value) => value.isNotEmpty && value != 'null')
              .firstOrNull;
      if (name != null) linkedNames.add(name);
    }
    final relationType = asset.type == WaterAssetType.dam
        ? context.l10n.hydroReservoir
        : context.l10n.hydroDam;
    final relationIcon = asset.type == WaterAssetType.dam
        ? Icons.water_rounded
        : Icons.account_balance_rounded;
    for (final name in linkedNames.take(2)) {
      relationships.add(
        HydroRelationshipItem(
          label: isRomanian ? 'Asociat' : 'Related',
          title: name,
          typeLabel: relationType,
          icon: relationIcon,
        ),
      );
    }
    return relationships;
  }

  List<HydroRelationshipItem> _riverRelationships(WaterRiverDetail? detail) {
    if (detail == null) return const <HydroRelationshipItem>[];
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return <HydroRelationshipItem>[
      if (detail.reservoirs.firstOrNull case final reservoir?)
        HydroRelationshipItem(
          label: isRomanian ? 'Asociat' : 'Related',
          title: reservoir.name,
          typeLabel: context.l10n.hydroReservoir,
          icon: Icons.water_rounded,
        ),
      if (detail.dams.firstOrNull case final dam?)
        HydroRelationshipItem(
          label: isRomanian ? 'Asociat' : 'Related',
          title: dam.name,
          typeLabel: context.l10n.hydroDam,
          icon: Icons.account_balance_rounded,
        ),
      if (detail.stations.firstOrNull case final station?)
        HydroRelationshipItem(
          label: isRomanian ? 'Relevant' : 'Relevant',
          title: station.name,
          typeLabel: context.l10n.hydroStation,
          icon: Icons.speed_rounded,
        ),
    ];
  }

  String _localizedTrend(String value) => switch (value.toLowerCase()) {
    'rising' => context.l10n.rising,
    'stable' => context.l10n.stable,
    'falling' => context.l10n.falling,
    _ => context.l10n.hydroEvidenceUnknown,
  };

  List<HydroRelationshipItem> _hydropowerRelationships(
    WaterMapPin plant,
    HydropowerPlantState? state,
  ) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return <HydroRelationshipItem>[
      if (plant.riverName?.isNotEmpty == true)
        HydroRelationshipItem(
          label: isRomanian ? 'Pe apă' : 'On water',
          title: plant.riverName!,
          typeLabel: context.l10n.hydroRiver,
          icon: Icons.waves_rounded,
        ),
      if (state?.reservoirId != null)
        HydroRelationshipItem(
          label: isRomanian ? 'Aici' : 'Here',
          title: isRomanian ? 'Acumulare asociată' : 'Linked reservoir',
          typeLabel: context.l10n.hydroReservoir,
          icon: Icons.water_rounded,
        ),
      if (state?.damId != null)
        HydroRelationshipItem(
          label: isRomanian ? 'Aici' : 'Here',
          title: isRomanian ? 'Baraj asociat' : 'Linked dam',
          typeLabel: context.l10n.hydroDam,
          icon: Icons.account_balance_rounded,
        ),
    ];
  }

  bool _isOfficialOrAnalyticalEvidence(String? value) {
    final normalized = value?.toUpperCase() ?? '';
    return normalized.contains('OFFICIAL') ||
        normalized.contains('MEASURED') ||
        normalized.contains('DERIVED') ||
        normalized.contains('CALCULATED') ||
        normalized.contains('ESTIMATED') ||
        normalized.contains('MODEL');
  }

  String _evidenceExplanation(String value) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final normalized = value.toUpperCase();
    if (normalized.contains('MEASURED') || normalized.contains('OFFICIAL')) {
      return isRomanian ? 'Măsurare oficială' : 'Official measurement';
    }
    if (normalized.contains('DERIVED') || normalized.contains('CALCULATED')) {
      return isRomanian
          ? 'Calculat din date verificate'
          : 'Calculated from verified data';
    }
    if (normalized.contains('ESTIMATED') || normalized.contains('MODEL')) {
      return isRomanian ? 'Valoare estimată' : 'Estimated value';
    }
    if (normalized.contains('OBSERVED') || normalized.contains('COMMUNITY')) {
      return isRomanian ? 'Observație comunitară' : 'Community observation';
    }
    return isRomanian ? 'Stare neconfirmată' : 'Unconfirmed status';
  }

  String? _humanSourceLabel(String? value) {
    final source = value?.trim();
    if (source == null ||
        source.isEmpty ||
        source.toLowerCase() == 'unavailable' ||
        source.toLowerCase() == 'unknown') {
      return null;
    }
    final normalized = source.toUpperCase();
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    if (normalized.contains('ANAR')) return 'ANAR';
    if (normalized.contains('MAPBOX') || normalized.contains('GEOMETR')) {
      return isRomanian ? 'Geometrie cartografică' : 'Map geometry';
    }
    if (normalized.contains('COMMUNITY')) {
      return isRomanian ? 'Observații comunitare' : 'Community observations';
    }
    if (normalized.contains('OFFICIAL') || normalized.contains('MEASURED')) {
      return isRomanian ? 'Sursă oficială' : 'Official source';
    }
    if (normalized.contains('DERIVED') || normalized.contains('CALCULATED')) {
      return isRomanian ? 'Date operaționale' : 'Operational data';
    }
    if (normalized.contains('MODEL') || normalized.contains('ESTIMATED')) {
      return isRomanian ? 'Model estimativ' : 'Estimation model';
    }
    return source;
  }

  String _confidenceExplanation(double confidence) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    if (confidence >= .8) {
      return isRomanian ? 'Încredere ridicată' : 'High confidence';
    }
    if (confidence >= .5) {
      return isRomanian ? 'Încredere medie' : 'Medium confidence';
    }
    return isRomanian ? 'Încredere limitată' : 'Limited confidence';
  }

  String _localizedOperation(String value) => switch (value.toUpperCase()) {
    'ACTIVE' => context.l10n.hydroActive,
    'INACTIVE' => context.l10n.hydroInactive,
    'POSSIBLE_ACTIVE' => context.l10n.hydroPossiblyActive,
    _ => context.l10n.hydroEvidenceUnknown,
  };

  String _hydroFreshnessLabel(DateTime? timestamp) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    if (timestamp == null || timestamp.millisecondsSinceEpoch <= 0) {
      return isRomanian
          ? 'Ora actualizării indisponibilă'
          : 'Update time unavailable';
    }
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final measuredAge = now.difference(local);
    final age = measuredAge.isNegative ? Duration.zero : measuredAge;
    if (age.inMinutes < 1) {
      return isRomanian ? 'Actualizat acum' : 'Updated now';
    }
    if (age.inMinutes < 60) {
      return isRomanian
          ? 'Actualizat acum ${age.inMinutes} min'
          : 'Updated ${age.inMinutes} min ago';
    }
    if (age.inHours < 24) {
      final hours = age.inHours;
      return isRomanian
          ? 'Actualizat acum $hours ${hours == 1 ? 'oră' : 'ore'}'
          : 'Updated $hours ${hours == 1 ? 'hour' : 'hours'} ago';
    }
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    if (age.inHours < 48) {
      return isRomanian
          ? 'Actualizat ieri la $hour:$minute'
          : 'Updated yesterday at $hour:$minute';
    }
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return isRomanian
        ? 'Actualizat $day.$month.${local.year} la $hour:$minute'
        : 'Updated ${local.year}-$month-$day at $hour:$minute';
  }

  String _formatMetricValue(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  String _formatSignedMetric(double value) {
    final magnitude = _formatMetricValue(value.abs());
    if (value > 0) return '+$magnitude';
    if (value < 0) return '−$magnitude';
    return magnitude;
  }

  int _hydroMetricPriority(String code) => switch (code.toLowerCase()) {
    'reservoir_level_m' || 'water_level_cm' => 0,
    'reservoir_volume_million_m3' => 1,
    'filling_percent' => 2,
    _ => 10,
  };

  String _hydroMetricLabel(WaterOperationalMetric metric) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return switch (metric.code.toLowerCase()) {
      'reservoir_level_m' => isRomanian ? 'Nivel acumulare' : 'Reservoir level',
      'water_level_cm' => isRomanian ? 'Nivel apă' : 'Water level',
      'reservoir_volume_million_m3' =>
        isRomanian ? 'Volum curent' : 'Current volume',
      'filling_percent' => isRomanian ? 'Grad de umplere' : 'Filling level',
      'inflow_m3s' => isRomanian ? 'Debit afluent' : 'Inflow',
      'outflow_m3s' => isRomanian ? 'Debit evacuat' : 'Outflow',
      _ => metric.name?.trim().isNotEmpty == true ? metric.name! : metric.code,
    };
  }

  void _closeHydroPanel() {
    setState(() {
      _previewStation = null;
      _temporarilyHighlightedStation = null;
      _previewWaterAsset = null;
      _previewWaterAssetDetail = null;
      _previewWaterAssetState = null;
      _previewHydropowerPin = null;
      _previewHydropowerState = null;
      _hydroPublicSelection = null;
      _previewRiver = null;
      _previewRiverDetail = null;
      _previewRiverState = null;
      _isLoadingHydroSelection = false;
      _isHydroPanelExpanded = false;
    });
    ref.read(selectedContextProvider.notifier).clear();
    unawaited(_syncStationAnnotations());
    unawaited(_syncWaterAssetAnnotations());
    unawaited(_syncHydropowerAnnotations());
    unawaited(_applyHydroRuntime());
  }

  Future<void> _openHydroPanelDetails() async {
    if (_previewStation case final station?) {
      await _openStation(station);
      return;
    }
    if (_previewWaterAsset case final asset?) {
      await _openWaterAsset(asset);
      return;
    }
    if (_previewHydropowerPin case final plant?) {
      await _openHydropowerDetails(plant);
      return;
    }
    if (_previewRiver case final river?) {
      await AppNavigator.open<void>(
        context,
        AppDestination.river,
        arguments: river,
      );
    }
  }

  Future<void> _toggleHydroPanelFavorite() async {
    if (_previewStation case final station?) {
      await _toggleFavorite(station);
    } else if (_previewWaterAsset case final asset?) {
      await _toggleWaterAssetFavorite(asset);
    } else if (_previewHydropowerPin case final plant?) {
      await _toggleHydropowerFavorite(plant);
    } else if (_previewRiver case final river?) {
      await _toggleRiverFavorite(river);
    }
  }

  Future<void> _toggleRiverFavorite(WaterRiverRef river) async {
    final key = 'river:${river.key}';
    final isSaved = _savedWaterAssetKeys.contains(key);
    try {
      if (isSaved) {
        await _savedItemsService.remove(type: 'river', referenceId: river.key);
      } else {
        await _savedItemsService.save(
          type: 'river',
          referenceId: river.key,
          title: river.name,
          subtitle: river.basinNames.firstOrNull,
          metadata: <String, Object?>{
            'source': river.provenanceSource,
            'river_key': river.key,
            'water_body_id': river.waterBodyId,
            'canonical_key': river.canonicalKey,
          },
        );
      }
      if (!mounted) return;
      setState(() {
        final next = <String>{..._savedWaterAssetKeys};
        isSaved ? next.remove(key) : next.add(key);
        _savedWaterAssetKeys = next;
      });
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apele mele nu sunt disponibile momentan.'),
        ),
      );
    }
  }

  Future<void> _openHydroWaterIntelligence() async {
    final station = _previewStation;
    if (station == null) return;
    ref.read(selectedContextProvider.notifier).publishStation(station);
    await AppNavigator.open<void>(
      context,
      AppDestination.water,
      arguments: WaterHubRequest(initialStation: station),
    );
  }

  bool get _hasValidHydroWaterContext => _previewStation != null;

  bool get _hasHydroAlertTarget {
    if (_previewStation != null || _previewWaterAsset != null) return true;
    if (_previewRiver case final river?) return river.waterBodyId != null;
    return false;
  }

  Future<void> _openHydroAlert() async {
    Object? arguments;
    if (_previewStation case final station?) {
      arguments = station;
    } else if (_previewWaterAsset case final asset?) {
      arguments = asset;
    } else if (_previewRiver case final river?) {
      arguments = river;
    }
    await AppNavigator.open<void>(
      context,
      AppDestination.newAlert,
      arguments: arguments,
    );
  }

  Future<void> _centerHydroSelection() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    final coordinates = switch ((
      _previewStation,
      _previewWaterAsset,
      _previewHydropowerPin,
      _hydroPublicSelection,
    )) {
      (final Station station, _, _, _) => (station.latitude, station.longitude),
      (_, final WaterAssetRef asset, _, _) => (asset.latitude, asset.longitude),
      (_, _, final WaterMapPin plant, _) => (plant.latitude, plant.longitude),
      (_, _, _, final HydroPublicFeatureSelection selection) => (
        selection.latitude,
        selection.longitude,
      ),
      _ => null,
    };
    if (coordinates == null) return;
    await mapboxMap.easeTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(coordinates.$2, coordinates.$1),
        ),
        zoom: _cameraZoom < 11 ? 11 : _cameraZoom,
      ),
      mapbox.MapAnimationOptions(duration: 420),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fluviAccessTierProvider);
    ref.listen<FluviAccessTier>(fluviAccessTierProvider, (previous, next) {
      unawaited(_applyHydroRuntime());
      unawaited(_refreshWaterAssetsAtCamera(force: true));
    });
    final canonical = ref.watch(currentLocationProvider);
    final deviceLocation = canonical.location;
    if (canonical.hasUsableLocation && deviceLocation != null) {
      _currentLocation = LatLng(
        deviceLocation.latitude,
        deviceLocation.longitude,
      );
      _locationUnavailableMessage = null;
    }
    final activeTarget = _cameraCoordinator.activeTarget;
    final initialCenter = activeTarget == null
        ? _currentLocation
        : LatLng(activeTarget.latitude, activeTarget.longitude);
    final isRomanian = Localizations.localeOf(context).languageCode == 'ro';
    final hydroPanelData = _hydroPanelData();

    return Scaffold(
      backgroundColor: const Color(0xFF071217),
      body: SafeArea(
        bottom: widget.includeBottomSafeArea,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalInset = constraints.biggest.shortestSide >= 600
                ? 24.0
                : 16.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                MapboxMapView(
                  key: const ValueKey('aifishmap-map-page-mapbox'),
                  styleUri: _selectedMapStyle.uri,
                  initialCenter: initialCenter,
                  onMapCreated: _onMapCreated,
                  onStyleLoaded: _onStyleLoaded,
                  onMapIdle: _handleMapIdle,
                  onMapTap: _handleHydroMapTap,
                ),
                Positioned(
                  left: horizontalInset,
                  right: horizontalInset,
                  top: 10,
                  child: Row(
                    children: [
                      if (widget.onBack != null) ...[
                        _MapReviewSquareButton(
                          key: const ValueKey('contextual-map-back'),
                          width: 46,
                          icon: Icons.arrow_back_rounded,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).backButtonTooltip,
                          onTap: widget.onBack!,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Material(
                          color: const Color(0xF0071015),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFF253841)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const ValueKey('figma-full-map-search'),
                            onTap: _openSearch,
                            child: SizedBox(
                              height: 46,
                              child: Row(
                                children: [
                                  const SizedBox(width: 13),
                                  const Icon(
                                    Icons.search_rounded,
                                    color: Color(0xFFF6F9FB),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      isRomanian
                                          ? 'Caută apă, stație, acces…'
                                          : 'Search water, station, access…',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF93A5AF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _MapReviewSquareButton(
                        key: const ValueKey('figma-full-map-layers'),
                        width: 62,
                        icon: _selectedMapStyle.icon,
                        tooltip: isRomanian ? 'Stil hartă' : 'Map style',
                        onTap: _openHydroLayerControls,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: horizontalInset,
                  right: horizontalInset,
                  top: 66,
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        _HydroMapControlChip(
                          active: _effectiveHydroPreferences.enabled,
                          locked: !_hasPremiumWater,
                          label: context.l10n.hydroPro,
                          onTap: _toggleHydroFromMap,
                          onExplore: _exploreHydroRomania,
                        ),
                        const SizedBox(width: 6),
                        _MapReviewFilterChip(
                          width: 70,
                          label: context.l10n.hydroStations.toUpperCase(),
                          active: _stationLayerVisible,
                          onTap: () {
                            setState(
                              () =>
                                  _stationLayerVisible = !_stationLayerVisible,
                            );
                            unawaited(_syncStationAnnotations());
                          },
                        ),
                        const SizedBox(width: 6),
                        _MapReviewFilterChip(
                          width: 72,
                          label: isRomanian ? 'RAPOARTE' : 'REPORTS',
                          active: _communityReportsVisible,
                          onTap: () {
                            setState(
                              () => _communityReportsVisible =
                                  !_communityReportsVisible,
                            );
                            unawaited(_syncReportAnnotations());
                          },
                        ),
                        const SizedBox(width: 6),
                        _MapReviewFilterChip(
                          width: 70,
                          label: isRomanian ? 'CAPTURI' : 'CATCHES',
                          active: _publicCatchesVisible,
                          onTap: () {
                            setState(
                              () => _publicCatchesVisible =
                                  !_publicCatchesVisible,
                            );
                            unawaited(_syncCatchAnnotations());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (_boatNavigationState != _BoatNavigationState.off)
                  Positioned(
                    right: horizontalInset,
                    top: 122,
                    child: _BoatNavigationHud(
                      state: _boatNavigationState,
                      speedKmh: _gpsSpeedKmh,
                      headingDegrees: _gpsHeadingDegrees,
                      onStart: () => unawaited(_startBoatNavigation()),
                      onStop: () =>
                          unawaited(_stopBoatNavigation(close: false)),
                      onClose: () =>
                          unawaited(_stopBoatNavigation(close: true)),
                    ),
                  ),
                if (_previewStation == null &&
                    _previewWaterAsset == null &&
                    _previewHydropowerPin == null &&
                    _hydroPublicSelection == null) ...[
                  Positioned(
                    right: horizontalInset,
                    bottom: 118,
                    child: Column(
                      children: [
                        _MapReviewSquareButton(
                          key: const ValueKey('figma-full-map-locate'),
                          icon: Icons.my_location_rounded,
                          tooltip: context.l10n.youAreHere,
                          isLoading: _isLocating,
                          onTap: () => _locateUser(recenter: true),
                        ),
                        const SizedBox(height: 8),
                        _MapReviewSquareButton(
                          key: const ValueKey('figma-full-map-boat-navigation'),
                          icon: Icons.directions_boat_filled_rounded,
                          tooltip: isRomanian
                              ? 'Navigație barcă'
                              : 'Boat navigation',
                          accent: const Color(0xFF43D9CC),
                          onTap: _toggleBoatNavigationPanel,
                        ),
                        const SizedBox(height: 8),
                        _MapReviewSquareButton(
                          key: const ValueKey('figma-full-map-quick-report'),
                          icon: Icons.add_rounded,
                          tooltip: isRomanian ? 'Raport rapid' : 'Quick report',
                          accent: const Color(0xFFF0BD55),
                          onTap: () => widget.onCreateReport(
                            ReportCategory.fishActivity,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: DraggableAskFluviControl(
                      controlKey: const ValueKey('map-ask-fluvi'),
                      scope: AskFluviPlacementScope.fullMap,
                      controlSize: const Size(140, 48),
                      defaultNormalizedPosition: const Offset(0, .76),
                      workspaceBuilder: (size) => Rect.fromLTRB(
                        horizontalInset,
                        120,
                        size.width - horizontalInset,
                        size.height - 16,
                      ),
                      obstaclesBuilder: (size) => <Rect>[
                        Rect.fromLTWH(
                          size.width - horizontalInset - 118,
                          110,
                          118,
                          68,
                        ),
                        Rect.fromLTWH(horizontalInset, 120, 164, 48),
                        Rect.fromLTWH(
                          size.width - horizontalInset - 48,
                          size.height - 222,
                          48,
                          104,
                        ),
                        if (_stationLoadError != null)
                          Rect.fromLTWH(
                            horizontalInset,
                            size.height - 128,
                            size.width - horizontalInset * 2,
                            44,
                          ),
                        if (_locationUnavailableMessage != null)
                          Rect.fromLTWH(
                            horizontalInset,
                            size.height -
                                (_stationLoadError == null ? 128 : 174),
                            size.width - horizontalInset * 2,
                            44,
                          ),
                      ],
                      semanticLabel: isRomanian
                          ? 'Întreabă Fluvi'
                          : 'Ask Fluvi',
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.askFluvi,
                      ),
                      child: _MapAskFluviButton(
                        onTap: () => AppNavigator.open<void>(
                          context,
                          AppDestination.askFluvi,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_stationLoadError != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: 84,
                    child: _MapMessage(text: _stationLoadError!),
                  ),
                if (_waterAssetLoadError != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: _stationLoadError == null ? 84 : 130,
                    child: _MapMessage(text: _waterAssetLoadError!),
                  ),
                if (_locationUnavailableMessage != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom:
                        _stationLoadError == null &&
                            _waterAssetLoadError == null
                        ? 84
                        : _stationLoadError != null &&
                              _waterAssetLoadError != null
                        ? 176
                        : 130,
                    child: _MapMessage(text: _locationUnavailableMessage!),
                  ),
                if (_effectiveHydroPreferences.enabled &&
                    hydroPanelData != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: 82,
                    child: HydroIntelligencePanel(
                      data: hydroPanelData,
                      expanded: _isHydroPanelExpanded,
                      isFavorite: _previewStation != null
                          ? _favoriteStationIds.contains(_previewStation!.id)
                          : _previewWaterAsset != null
                          ? _savedWaterAssetKeys.contains(
                              '${_previewWaterAsset!.entityType}:${_previewWaterAsset!.id}',
                            )
                          : _previewHydropowerPin != null
                          ? _savedWaterAssetKeys.contains(
                              'hydropower:${_previewHydropowerPin!.entityId}',
                            )
                          : _previewRiver != null
                          ? _savedWaterAssetKeys.contains(
                              'river:${_previewRiver!.key}',
                            )
                          : false,
                      detailsLabel: context.l10n.hydroDetails,
                      graphLabel: context.l10n.hydroViewGraph,
                      askLabel: context.l10n.hydroAskFluvi,
                      sourceLabel: context.l10n.source,
                      updatedLabel: context.l10n.hydroUpdated,
                      onToggleExpanded: () => setState(
                        () => _isHydroPanelExpanded = !_isHydroPanelExpanded,
                      ),
                      onClose: _closeHydroPanel,
                      onFavorite:
                          _previewStation != null ||
                              _previewWaterAsset != null ||
                              _previewHydropowerPin != null ||
                              _previewRiver != null
                          ? _toggleHydroPanelFavorite
                          : null,
                      onDetails:
                          _previewStation != null ||
                              _previewWaterAsset != null ||
                              _previewHydropowerPin != null ||
                              _previewRiver != null
                          ? _openHydroPanelDetails
                          : null,
                      onWaterIntelligence: _hasValidHydroWaterContext
                          ? _openHydroWaterIntelligence
                          : null,
                      onAlert: _hasHydroAlertTarget ? _openHydroAlert : null,
                      onCenter: _centerHydroSelection,
                      onGraph: _previewStation == null
                          ? null
                          : () => _openStation(_previewStation!),
                      onAsk: () => AppNavigator.open<void>(
                        context,
                        AppDestination.askFluvi,
                      ),
                    ),
                  ),
                if (!_effectiveHydroPreferences.enabled &&
                    _previewStation != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: 82,
                    child: FullMapPinPreviewCard(
                      station: _previewStation!,
                      isFavorite: _favoriteStationIds.contains(
                        _previewStation!.id,
                      ),
                      onClose: () {
                        setState(() {
                          _previewStation = null;
                          _temporarilyHighlightedStation = null;
                        });
                        unawaited(_syncStationAnnotations());
                      },
                      onDetails: () => _openStation(_previewStation!),
                      onFavorite: () => _toggleFavorite(_previewStation!),
                      onAlert: () => AppNavigator.open<void>(
                        context,
                        AppDestination.newAlert,
                        arguments: _previewStation!,
                      ),
                    ),
                  ),
                if (!_effectiveHydroPreferences.enabled &&
                    _previewWaterAsset != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: 82,
                    child: FullMapWaterAssetPreviewCard(
                      asset: _previewWaterAsset!,
                      isFavorite: _savedWaterAssetKeys.contains(
                        '${_previewWaterAsset!.entityType}:${_previewWaterAsset!.id}',
                      ),
                      onClose: () {
                        setState(() => _previewWaterAsset = null);
                        unawaited(_syncWaterAssetAnnotations());
                      },
                      onDetails: () => _openWaterAsset(_previewWaterAsset!),
                      onFavorite: () =>
                          _toggleWaterAssetFavorite(_previewWaterAsset!),
                      onReport: () => AppNavigator.open<void>(
                        context,
                        AppDestination.addReport,
                      ),
                    ),
                  ),
                if (!_effectiveHydroPreferences.enabled &&
                    _previewHydropowerPin != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: 82,
                    child: FullMapHydropowerPreviewCard(
                      pin: _previewHydropowerPin!,
                      state: _previewHydropowerState,
                      isFavorite: _savedWaterAssetKeys.contains(
                        'hydropower:${_previewHydropowerPin!.entityId}',
                      ),
                      onClose: () {
                        setState(() {
                          _previewHydropowerPin = null;
                          _previewHydropowerState = null;
                        });
                        unawaited(_syncHydropowerAnnotations());
                      },
                      onDetails: () =>
                          _openHydropowerDetails(_previewHydropowerPin!),
                      onFavorite: () =>
                          _toggleHydropowerFavorite(_previewHydropowerPin!),
                      onReport: () => AppNavigator.open<void>(
                        context,
                        AppDestination.addReport,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _mapboxColor(Color color) {
    return ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
  }
}

String _boatHeadingLabel(double? degrees) {
  if (degrees == null || !degrees.isFinite) return '--';
  const labels = ['N', 'NE', 'E', 'SE', 'S', 'SV', 'V', 'NV'];
  final normalized = ((degrees % 360) + 360) % 360;
  return labels[((normalized + 22.5) ~/ 45) % labels.length];
}

class _BoatNavigationHud extends StatelessWidget {
  const _BoatNavigationHud({
    required this.state,
    required this.speedKmh,
    required this.headingDegrees,
    required this.onStart,
    required this.onStop,
    required this.onClose,
  });

  final _BoatNavigationState state;
  final double? speedKmh;
  final double? headingDegrees;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final running = state == _BoatNavigationState.running;

    final speed = running && speedKmh != null && speedKmh!.isFinite
        ? speedKmh!.toStringAsFixed(1).replaceAll('.', ',')
        : '--';

    final heading =
        running && headingDegrees != null && headingDegrees!.isFinite
        ? '${headingDegrees!.round()}\u00B0'
        : '--';

    return Container(
      key: const ValueKey('figma-full-map-boat-hud'),
      width: 154,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        color: const Color(0xEB071015),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xEB253841)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: .785398,
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Color(0xFF43D9CC),
                  size: 17,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                running ? _boatHeadingLabel(headingDegrees) : '--',
                style: const TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  color: Color(0xFF43D9CC),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  heading,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    color: Color(0xFF93A5AF),
                    fontSize: 9,
                  ),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: running
                      ? const Color(0xFF34D399)
                      : const Color(0xFF647780),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Color(0xFF93A5AF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          speed,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFFF6F9FB),
                            fontSize: 20,
                            height: 1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 1),
                      child: Text(
                        'km/h',
                        style: TextStyle(
                          color: Color(0xFF93A5AF),
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                height: 27,
                child: TextButton(
                  key: ValueKey(
                    running ? 'boat-navigation-stop' : 'boat-navigation-start',
                  ),
                  onPressed: running ? onStop : onStart,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    minimumSize: const Size(50, 27),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: running
                        ? const Color(0xFFF6F9FB)
                        : const Color(0xFF43D9CC),
                    backgroundColor: const Color(0xFF13232A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      running ? 'STOP' : 'START',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .25,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HydroMapControlChip extends StatelessWidget {
  const _HydroMapControlChip({
    required this.active,
    required this.locked,
    required this.label,
    required this.onTap,
    required this.onExplore,
  });

  final bool active;
  final bool locked;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: active ? const Color(0xED0B2E38) : const Color(0xE80C171D),
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? const Color(0xFF43E4E0) : const Color(0xFF536873),
          width: active ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('hydro-pro-map-control'),
        onTap: onTap,
        onLongPress: onExplore,
        child: SizedBox(
          width: 118,
          height: 42,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                locked ? Icons.lock_outline_rounded : Icons.waves_rounded,
                color: active
                    ? const Color(0xFF43E4E0)
                    : const Color(0xFF9EB0BA),
                size: 15,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active
                        ? const Color(0xFFE8FFFF)
                        : const Color(0xFFB0BEC5),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .45,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF19BFC8).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'RO',
                  style: TextStyle(
                    color: Color(0xFF67EFF0),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HydroLayerSelection {
  const _HydroLayerSelection({
    required this.style,
    required this.preferences,
    required this.stationLayerVisible,
    required this.hydropowerLayerVisible,
    this.requestUpgrade = false,
    this.exploreRomania = false,
  });

  final _FullMapStyle style;
  final HydroOverlayPreferences preferences;
  final bool stationLayerVisible;
  final bool hydropowerLayerVisible;
  final bool requestUpgrade;
  final bool exploreRomania;
}

class _HydroLayerSheet extends StatefulWidget {
  const _HydroLayerSheet({
    required this.initialStyle,
    required this.initialPreferences,
    required this.stationLayerVisible,
    required this.hydropowerLayerVisible,
    required this.hasPremium,
  });

  final _FullMapStyle initialStyle;
  final HydroOverlayPreferences initialPreferences;
  final bool stationLayerVisible;
  final bool hydropowerLayerVisible;
  final bool hasPremium;

  @override
  State<_HydroLayerSheet> createState() => _HydroLayerSheetState();
}

class _HydroLayerSheetState extends State<_HydroLayerSheet> {
  late _FullMapStyle _style;
  late HydroOverlayPreferences _preferences;
  late bool _stations;
  late bool _plants;

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
    _preferences = widget.initialPreferences;
    _stations = widget.stationLayerVisible;
    _plants = widget.hydropowerLayerVisible;
  }

  _HydroLayerSelection _result({
    bool requestUpgrade = false,
    bool exploreRomania = false,
  }) => _HydroLayerSelection(
    style: _style,
    preferences: _preferences,
    stationLayerVisible: _stations,
    hydropowerLayerVisible: _plants,
    requestUpgrade: requestUpgrade,
    exploreRomania: exploreRomania,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = widget.hasPremium && _preferences.enabled;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0A141A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: Color(0xFF29414C))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 9),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF5F747E),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 10, 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22CFD4).withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.layers_rounded,
                      color: Color(0xFF54E4E4),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.mapLayers,
                          style: const TextStyle(
                            color: Color(0xFFF3FAFD),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          l10n.hydroRomaniaPack,
                          style: const TextStyle(
                            color: Color(0xFF89A2AF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFFCAD8DE),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                key: const ValueKey('full-map-approved-filters'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                children: <Widget>[
                  _HydroSectionLabel(label: l10n.hydroBaseMap),
                  const SizedBox(height: 8),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 3.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: _FullMapStyle.values
                        .map(
                          (style) => _HydroBasemapOption(
                            icon: style.icon,
                            label: switch (style) {
                              _FullMapStyle.standard => l10n.standard,
                              _FullMapStyle.satellite => l10n.satellite,
                              _FullMapStyle.outdoors => l10n.hydroOutdoors,
                              _FullMapStyle.streets => l10n.hydroStreets,
                            },
                            selected: style == _style,
                            onTap: () => setState(() => _style = style),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 18),
                  _HydroSectionLabel(label: l10n.hydroPremiumOverlay),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF102A32), Color(0xFF101C23)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF42DDD9)
                            : const Color(0xFF344A55),
                      ),
                    ),
                    child: SwitchListTile.adaptive(
                      key: const ValueKey('hydro-overlay-premium-toggle'),
                      secondary: Icon(
                        widget.hasPremium
                            ? Icons.waves_rounded
                            : Icons.lock_outline_rounded,
                        color: const Color(0xFF50E1DF),
                      ),
                      title: Text(
                        l10n.hydroMapTitle,
                        style: const TextStyle(
                          color: Color(0xFFF0FAFC),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        widget.hasPremium
                            ? (active ? l10n.hydroEnabled : l10n.hydroDisabled)
                            : l10n.hydroProRequired,
                        style: const TextStyle(color: Color(0xFF8CA6B2)),
                      ),
                      value: active,
                      activeThumbColor: const Color(0xFF54E8E3),
                      onChanged: (_) {
                        if (!widget.hasPremium) {
                          Navigator.of(
                            context,
                          ).pop(_result(requestUpgrade: true));
                          return;
                        }
                        setState(
                          () => _preferences = _preferences.copyWith(
                            enabled: !_preferences.enabled,
                          ),
                        );
                      },
                    ),
                  ),
                  if (active) ...<Widget>[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _HydroSublayerChip(
                          key: const ValueKey('hydro-sublayer-rivers'),
                          icon: Icons.waves_rounded,
                          label: l10n.hydroRivers,
                          selected: _preferences.rivers,
                          onSelected: (value) => setState(
                            () => _preferences = _preferences.copyWith(
                              rivers: value,
                            ),
                          ),
                        ),
                        _HydroSublayerChip(
                          key: const ValueKey('hydro-sublayer-reservoirs'),
                          icon: Icons.water_rounded,
                          label: l10n.hydroReservoirs,
                          selected: _preferences.reservoirs,
                          onSelected: (value) => setState(
                            () => _preferences = _preferences.copyWith(
                              reservoirs: value,
                            ),
                          ),
                        ),
                        _HydroSublayerChip(
                          key: const ValueKey('hydro-sublayer-dams'),
                          icon: Icons.account_balance_rounded,
                          label: l10n.hydroDams,
                          selected: _preferences.dams,
                          onSelected: (value) => setState(
                            () => _preferences = _preferences.copyWith(
                              dams: value,
                            ),
                          ),
                        ),
                        _HydroSublayerChip(
                          key: const ValueKey('full-map-filter-stations'),
                          icon: Icons.speed_rounded,
                          label: l10n.hydroStations,
                          selected: _stations,
                          onSelected: (value) =>
                              setState(() => _stations = value),
                        ),
                        _HydroSublayerChip(
                          key: const ValueKey('full-map-filter-hydropower'),
                          icon: Icons.bolt_rounded,
                          label: l10n.hydroPlants,
                          selected: _plants,
                          onSelected: (value) =>
                              setState(() => _plants = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('hydro-explore-romania'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_result(exploreRomania: true)),
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: Text(l10n.hydroExploreRomania),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF63E9E5),
                        side: const BorderSide(color: Color(0xFF3ABEC1)),
                        minimumSize: const Size.fromHeight(44),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
              child: Row(
                children: <Widget>[
                  TextButton(
                    key: const ValueKey('full-map-filter-reset'),
                    onPressed: () => setState(() {
                      _style = _FullMapStyle.standard;
                      _preferences = const HydroOverlayPreferences();
                      _stations = true;
                      _plants = true;
                    }),
                    child: Text(l10n.hydroLayersReset),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('full-map-filter-apply'),
                    onPressed: () => Navigator.of(context).pop(_result()),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF18AEB7),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(112, 44),
                    ),
                    child: Text(l10n.hydroLayersApply),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HydroSectionLabel extends StatelessWidget {
  const _HydroSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: const TextStyle(
      color: Color(0xFF8199A5),
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: .8,
    ),
  );
}

class _HydroBasemapOption extends StatelessWidget {
  const _HydroBasemapOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF17343D) : const Color(0xFF111E25),
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFF46DCD9) : const Color(0xFF2A3C45),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: selected
                  ? const Color(0xFF57E7E2)
                  : const Color(0xFF8FA5AF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFF2FFFF)
                      : const Color(0xFFB8C6CC),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _HydroSublayerChip extends StatelessWidget {
  const _HydroSublayerChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    selected: selected,
    showCheckmark: false,
    avatar: Icon(
      icon,
      size: 16,
      color: selected ? const Color(0xFF50E3DF) : const Color(0xFF8EA3AD),
    ),
    label: Text(label),
    labelStyle: TextStyle(
      color: selected ? const Color(0xFFEFFFFF) : const Color(0xFFABBAC1),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    ),
    selectedColor: const Color(0xFF14353D),
    backgroundColor: const Color(0xFF111E25),
    side: BorderSide(
      color: selected ? const Color(0xFF39BEC1) : const Color(0xFF31434C),
    ),
    onSelected: onSelected,
  );
}

class _MapReviewFilterChip extends StatelessWidget {
  const _MapReviewFilterChip({
    required this.label,
    this.width,
    this.active = false,
    this.onTap,
  });

  final String label;
  final double? width;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF43D9CC) : const Color(0xFF93A5AF);
    final visual = Container(
      width: width,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xE60D2025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          color: color,
          fontSize: 8.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: label,
      child: SizedBox(
        width: width,
        height: 48,
        child: Align(
          alignment: Alignment.center,
          child: onTap == null
              ? visual
              : InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  child: visual,
                ),
        ),
      ),
    );
  }
}

class _MapReviewSquareButton extends StatelessWidget {
  const _MapReviewSquareButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.width = 48,
    this.accent,
    this.isLoading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double width;
  final Color? accent;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? const Color(0xFFF6F9FB);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        child: Material(
          color: const Color(0xF0071015),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent ?? const Color(0xFF253841)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: 48,
              child: Center(
                child: isLoading
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      )
                    : Icon(icon, color: color, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapAskFluviButton extends StatelessWidget {
  const _MapAskFluviButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Întreabă Fluvi',
    child: Material(
      color: const Color(0xF0071015),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF43D9CC)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 140,
          height: 48,
          child: Row(
            children: [
              SizedBox(width: 15),
              Icon(Icons.circle, size: 12, color: Color(0xFF43D9CC)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Întreabă Fluvi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFFF6F9FB),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 10),
            ],
          ),
        ),
      ),
    ),
  );
}

class FullMapHydropowerPreviewCard extends StatelessWidget {
  const FullMapHydropowerPreviewCard({
    super.key,
    required this.pin,
    required this.state,
    required this.isFavorite,
    required this.onClose,
    required this.onDetails,
    required this.onFavorite,
    required this.onReport,
  });

  final WaterMapPin pin;
  final HydropowerPlantState? state;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onDetails;
  final VoidCallback onFavorite;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final operationState = state?.operationState ?? pin.operationState;
    final confidence = state?.confidence ?? pin.confidence;
    final evidenceClass = state?.evidenceClass ?? pin.evidenceClass;
    final evidenceLabel = switch (evidenceClass) {
      'MEASURED' => 'MĂSURAT',
      'DERIVED' => 'CALCULAT',
      'ESTIMATED' => 'ML ESTIMAT',
      'OBSERVED' => 'OBSERVAT',
      _ => 'NECUNOSCUT',
    };
    final freshness = state?.freshnessStatus ?? pin.freshnessStatus;
    final freshnessLabel = switch (freshness) {
      'fresh' => 'ACTUAL',
      'recent' => 'RECENT',
      'stale' => 'VECHI',
      _ => 'FĂRĂ DATE',
    };
    final operationColor = switch (operationState) {
      'ACTIVE' => const Color(0xFF00E676),
      'INACTIVE' => const Color(0xFF78909C),
      'POSSIBLE_ACTIVE' => const Color(0xFFF59E0B),
      _ => const Color(0xFF78909C),
    };
    final operationLabel = switch (operationState) {
      'ACTIVE' => 'Uzinează',
      'INACTIVE' => 'Nu uzinează',
      'POSSIBLE_ACTIVE' => 'Posibil activă',
      _ => 'Stare necunoscută',
    };

    return Material(
      key: const ValueKey('full-map-hydropower-preview'),
      color: const Color(0xF20A1628),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: .45),
                    ),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFF59E0B),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        [
                          'Hidrocentrală',
                          if (pin.riverName?.isNotEmpty == true) pin.riverName!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8DA2B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                  color: const Color(0xFFF6F9FB),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.power_rounded, color: operationColor),
                const SizedBox(width: 7),
                Text(
                  operationLabel,
                  style: TextStyle(
                    color: operationColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  evidenceLabel,
                  style: TextStyle(
                    color: operationColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (confidence > 0) 'încredere ${(confidence * 100).round()}%',
                freshnessLabel,
                if (pin.communityReportCount > 0)
                  '${pin.communityReportCount} rapoarte recente',
              ].join(' · '),
              style: const TextStyle(color: Color(0xFF8DA2B8), fontSize: 10),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: isFavorite
                      ? 'Elimină din Apele mele'
                      : 'Adaugă în Apele mele',
                  onPressed: onFavorite,
                  color: const Color(0xFF43D9CC),
                  icon: Icon(
                    isFavorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Raportează observație locală',
                  onPressed: onReport,
                  color: const Color(0xFF43D9CC),
                  icon: const Icon(Icons.add_alert_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDetails,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF6F9FB),
                      side: const BorderSide(color: Color(0xFF43D9CC)),
                    ),
                    child: const Text('Vezi detalii'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FullMapWaterAssetPreviewCard extends StatelessWidget {
  const FullMapWaterAssetPreviewCard({
    super.key,
    required this.asset,
    required this.isFavorite,
    required this.onClose,
    required this.onDetails,
    required this.onFavorite,
    required this.onReport,
  });

  final WaterAssetRef asset;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onDetails;
  final VoidCallback onFavorite;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final trendColor = MapFeatureRegistry.waterStateColor(asset.stateTrend);
    final trendLabel = switch (asset.stateTrend) {
      'rising' => 'Crește',
      'stable' => 'Stabil',
      'falling' => 'Scade',
      _ => 'Necunoscut',
    };
    final sourceLabel = switch (asset.stateSource) {
      'official' || 'official_measured' => 'MĂSURAT',
      'calculated_from_operational_data' => 'CALCULAT',
      'model_estimated' => 'ML ESTIMAT',
      'official_plus_community' => 'OFICIAL + COMUNITATE',
      'community_observed' => 'OBSERVAT',
      _ => 'FĂRĂ DATE RECENTE',
    };
    return Material(
      key: const ValueKey('full-map-water-asset-preview'),
      color: const Color(0xF20A1628),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: trendColor.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: trendColor.withValues(alpha: .45),
                    ),
                  ),
                  child: Icon(
                    asset.type == WaterAssetType.dam
                        ? Icons.account_balance_rounded
                        : Icons.water_rounded,
                    color: trendColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        [
                          asset.type == WaterAssetType.dam
                              ? 'Baraj'
                              : 'Lac de acumulare',
                          if (asset.riverName?.isNotEmpty == true)
                            asset.riverName!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8DA2B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                  color: const Color(0xFFF6F9FB),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  asset.stateTrend == 'rising'
                      ? Icons.trending_up_rounded
                      : asset.stateTrend == 'falling'
                      ? Icons.trending_down_rounded
                      : asset.stateTrend == 'stable'
                      ? Icons.trending_flat_rounded
                      : Icons.help_outline_rounded,
                  color: trendColor,
                ),
                const SizedBox(width: 7),
                Text(
                  trendLabel,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  sourceLabel,
                  style: TextStyle(
                    color: trendColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .55,
                  ),
                ),
              ],
            ),
            if (asset.communityReportCount > 0 ||
                asset.stateConfidence > 0) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (asset.communityReportCount > 0)
                    '${asset.communityReportCount} rapoarte recente',
                  if (asset.stateConfidence > 0)
                    'încredere ${(asset.stateConfidence * 100).round()}%',
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF8DA2B8), fontSize: 10),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: isFavorite
                      ? 'Elimină din Apele mele'
                      : 'Adaugă în Apele mele',
                  onPressed: onFavorite,
                  color: const Color(0xFF43D9CC),
                  icon: Icon(
                    isFavorite
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Raportează starea apei',
                  onPressed: onReport,
                  color: const Color(0xFF43D9CC),
                  icon: const Icon(Icons.add_alert_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDetails,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF6F9FB),
                      side: const BorderSide(color: Color(0xFF43D9CC)),
                    ),
                    child: const Text('Vezi detalii'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FullMapPinPreviewCard extends StatelessWidget {
  const FullMapPinPreviewCard({
    super.key,
    required this.station,
    this.isFavorite = false,
    required this.onClose,
    required this.onDetails,
    required this.onFavorite,
    required this.onAlert,
  });

  final Station station;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onDetails;
  final VoidCallback onFavorite;
  final VoidCallback onAlert;

  @override
  Widget build(BuildContext context) {
    final river = station.river.trim();
    return Material(
      key: const ValueKey('full-map-pin-preview'),
      color: const Color(0xF20A1628),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              station.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox.square(dimension: 6),
                          ),
                        ],
                      ),
                      if (river.isNotEmpty)
                        Text(
                          river,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8DA2B8),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                  color: const Color(0xFFF6F9FB),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    station.hasWaterLevel
                        ? '${station.level.toStringAsFixed(0)} ${station.waterLevelUnit}'
                        : 'Nivel indisponibil',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isFavorite
                      ? 'Elimină din favorite'
                      : 'Adaugă la favorite',
                  onPressed: onFavorite,
                  color: const Color(0xFF43D9CC),
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Alertă',
                  onPressed: onAlert,
                  color: const Color(0xFF43D9CC),
                  icon: const Icon(Icons.notifications_none_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: onDetails,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF6F9FB),
                side: const BorderSide(color: Color(0xFF43D9CC)),
              ),
              child: const Text('Vezi detalii'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _MapFilterAction { style }

@immutable
class _FullMapFilterSelection {
  const _FullMapFilterSelection({
    this.stationLayerVisible = true,
    this.communityReportsVisible = true,
    this.favoriteStationsVisible = false,
    this.damLayerVisible = false,
    this.reservoirLayerVisible = false,
    this.hydropowerLayerVisible = true,
    this.radiusKm = 100,
    this.reportCategories = const {},
  });

  final bool stationLayerVisible;
  final bool communityReportsVisible;
  final bool favoriteStationsVisible;
  final bool damLayerVisible;
  final bool reservoirLayerVisible;
  final bool hydropowerLayerVisible;
  final double radiusKm;
  final Set<ReportCategory> reportCategories;

  _FullMapFilterSelection copyWith({
    bool? stationLayerVisible,
    bool? communityReportsVisible,
    bool? favoriteStationsVisible,
    bool? damLayerVisible,
    bool? reservoirLayerVisible,
    bool? hydropowerLayerVisible,
    double? radiusKm,
    Set<ReportCategory>? reportCategories,
  }) => _FullMapFilterSelection(
    stationLayerVisible: stationLayerVisible ?? this.stationLayerVisible,
    communityReportsVisible:
        communityReportsVisible ?? this.communityReportsVisible,
    favoriteStationsVisible:
        favoriteStationsVisible ?? this.favoriteStationsVisible,
    damLayerVisible: damLayerVisible ?? this.damLayerVisible,
    reservoirLayerVisible: reservoirLayerVisible ?? this.reservoirLayerVisible,
    hydropowerLayerVisible:
        hydropowerLayerVisible ?? this.hydropowerLayerVisible,
    radiusKm: radiusKm ?? this.radiusKm,
    reportCategories: Set.unmodifiable(
      reportCategories ?? this.reportCategories,
    ),
  );
}

class _MapStyleSelector extends StatelessWidget {
  const _MapStyleSelector({
    required this.selectedStyle,
    required this.languageCode,
  });

  final _FullMapStyle selectedStyle;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final isRomanian = languageCode == 'ro';
    final title = isRomanian ? 'Stil hartă' : 'Map style';

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0B141D).withValues(alpha: .98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: .11)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .42),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .22),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              for (final style in _FullMapStyle.values) ...[
                _MapStyleOption(
                  style: style,
                  label: _styleLabel(style, isRomanian: isRomanian),
                  selected: style == selectedStyle,
                ),
                if (style != _FullMapStyle.values.last)
                  const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _styleLabel(_FullMapStyle style, {required bool isRomanian}) =>
      switch (style) {
        _FullMapStyle.satellite => isRomanian ? 'Satelit' : 'Satellite',
        _FullMapStyle.standard => 'Standard',
        _FullMapStyle.outdoors => isRomanian ? 'Teren' : 'Outdoors',
        _FullMapStyle.streets => isRomanian ? 'Străzi' : 'Streets',
      };
}

class _MapStyleOption extends StatelessWidget {
  const _MapStyleOption({
    required this.style,
    required this.label,
    required this.selected,
  });

  final _FullMapStyle style;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF12D8D6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(style),
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: .11)
                : Colors.white.withValues(alpha: .035),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? accentColor.withValues(alpha: .42)
                  : Colors.white.withValues(alpha: .09),
            ),
          ),
          child: Row(
            children: [
              Icon(
                style.icon,
                size: 21,
                color: selected ? accentColor : Colors.white70,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? accentColor
                    : Colors.white.withValues(alpha: .28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapboxMapView extends StatefulWidget {
  const MapboxMapView({
    super.key,
    required this.styleUri,
    required this.initialCenter,
    required this.onMapCreated,
    required this.onStyleLoaded,
    required this.onMapIdle,
    required this.onMapTap,
  });

  final String styleUri;
  final LatLng? initialCenter;
  final ValueChanged<mapbox.MapboxMap> onMapCreated;
  final ValueChanged<mapbox.StyleLoadedEventData> onStyleLoaded;
  final ValueChanged<mapbox.MapIdleEventData> onMapIdle;
  final ValueChanged<mapbox.MapContentGestureContext> onMapTap;

  @override
  State<MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<MapboxMapView> {
  late final mapbox.ViewportState? _initialViewport =
      widget.initialCenter == null
      ? null
      : mapbox.CameraViewportState(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              widget.initialCenter!.longitude,
              widget.initialCenter!.latitude,
            ),
          ),
          zoom: 12.5,
        );

  @override
  Widget build(BuildContext context) {
    return mapbox.MapWidget(
      key: widget.key,
      textureView: true,
      styleUri: widget.styleUri,
      // Mapbox treats a newly-created ViewportState as a commanded
      // transition on widget updates. Keep the documented initial viewport
      // stable so unrelated Flutter rebuilds never overwrite user/programmatic
      // camera navigation.
      viewport: _initialViewport,
      onMapCreated: widget.onMapCreated,
      onStyleLoadedListener: widget.onStyleLoaded,
      onMapIdleListener: widget.onMapIdle,
      // ignore: deprecated_member_use
      onTapListener: widget.onMapTap,
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101720).withValues(alpha: .78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
