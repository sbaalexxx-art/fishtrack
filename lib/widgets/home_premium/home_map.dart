import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';
import '../../core/context/current_location.dart';
import '../../core/navigation/app_destination.dart';
import '../../core/navigation/app_navigator.dart';
import '../../services/community_service.dart';
import '../../services/location_service.dart';
import '../../services/map_search_service.dart';
import '../../services/station_filter_service.dart';
import 'home_premium_layout.dart';
import '../home/home_map.dart';

enum HomeMapLocationAvailability { locating, available, unavailable }

enum _HomeReportStreamState { sync, live, offline, error }

LatLng? homeMapDeviceCenter(CurrentLocationState state) {
  final location = state.location;
  if (!state.hasUsableLocation || location == null) return null;
  return LatLng(location.latitude, location.longitude);
}

LatLng? selectInitialHomeMapPhysicalCamera({
  required LatLng? current,
  required CurrentLocationState canonical,
}) => current ?? homeMapDeviceCenter(canonical);

enum HomeMapCameraIntent { automaticLocation, exploration, locate }

@immutable
class HomeMapCameraRequest {
  const HomeMapCameraRequest({
    required this.target,
    required this.zoom,
    required this.intent,
  });

  final LatLng target;
  final double zoom;
  final HomeMapCameraIntent intent;
}

HomeMapCameraRequest selectPendingHomeMapCameraRequest({
  required HomeMapCameraRequest? current,
  required HomeMapCameraRequest incoming,
}) {
  if (incoming.intent == HomeMapCameraIntent.automaticLocation &&
      current != null &&
      current.intent != HomeMapCameraIntent.automaticLocation) {
    return current;
  }
  return incoming;
}

bool shouldApplyAutomaticHomeMapCamera({
  required LatLng? explorationCenter,
  required bool didApplyInitialPhysicalCamera,
  required bool appliedPhysicalCameraWasCached,
  required CurrentLocationStatus resolvedStatus,
}) {
  if (explorationCenter != null) return false;
  if (!didApplyInitialPhysicalCamera) return true;
  return appliedPhysicalCameraWasCached &&
      resolvedStatus == CurrentLocationStatus.available;
}

LatLng? homeMapExplorationCenterAfterIntent({
  required LatLng? current,
  required HomeMapCameraIntent intent,
  LatLng? explorationTarget,
}) => switch (intent) {
  HomeMapCameraIntent.automaticLocation => current,
  HomeMapCameraIntent.exploration => explorationTarget,
  HomeMapCameraIntent.locate => null,
};

class HomePremiumMapController {
  VoidCallback? _recenter;

  void recenter() => _recenter?.call();

  void _attach(VoidCallback recenter) => _recenter = recenter;

  void _detach(VoidCallback recenter) {
    if (_recenter == recenter) _recenter = null;
  }
}

class HomePremiumMap extends ConsumerStatefulWidget {
  const HomePremiumMap({
    super.key,
    this.controller,
    this.onTap,
    this.child,
    this.embedded = false,
    this.showControls = true,
    this.onLocationAvailabilityChanged,
    this.onLocationLabelChanged,
  });

  final HomePremiumMapController? controller;
  final VoidCallback? onTap;
  final Widget? child;

  /// Uses compact controls and delegates outer clipping to the commercial Home.
  final bool embedded;

  /// When false, the parent screen owns all HUD controls.
  final bool showControls;

  final ValueChanged<HomeMapLocationAvailability>?
  onLocationAvailabilityChanged;
  final ValueChanged<String?>? onLocationLabelChanged;

  @override
  ConsumerState<HomePremiumMap> createState() => _HomePremiumMapState();
}

class _HomePremiumMapState extends ConsumerState<HomePremiumMap>
    with WidgetsBindingObserver {
  static const _defaultLocalRadiusKm = 100.0;
  static const _homeLayerOptions = <MapOverlay>[MapOverlay.communityReports];

  final CommunityService _communityService = const CommunityService();
  final Connectivity _connectivity = Connectivity();
  final MapSearchService _searchService = const MapSearchService();
  mapbox.MapboxMap? _mapboxMap;
  final StationFilterService _filterService = StationFilterService.instance;
  late Stream<List<CommunityPost>> _reportsStream;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Set<ReportCategory> _reportCategories = const {};
  LatLng? _explorationCenter;
  double _localRadiusKm = _defaultLocalRadiusKm;
  LatLng? _currentLocation;
  LatLng? _initialPhysicalCamera;
  bool _initialPhysicalCameraWasCached = false;
  String? _lastGpsLocationLabel;
  LocationFailureReason? _locationFailure;
  bool _isLocating = false;
  bool _queuedRecenterLocationRequest = false;
  int _locationRequestRevision = 0;
  int _locationLabelRevision = 0;
  bool _isMapReady = false;
  bool _didApplyInitialUserCamera = false;
  bool _initialUserCameraWasCached = false;
  HomeMapCameraRequest? _pendingCameraRequest;
  bool _isSearching = false;
  bool _connectivityKnown = false;
  bool _isDefinitelyOffline = false;
  final MapBaseLayer _baseLayer = MapBaseLayer.satellite;
  Set<MapOverlay> _overlays = const {MapOverlay.communityReports};

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(_handleLocationAction);
    WidgetsBinding.instance.addObserver(this);
    _reportsStream = _communityService.watchReports();
    _filterService.filters.addListener(_onFiltersChanged);
    if (widget.child == null) {
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectivity,
      );
      unawaited(_checkInitialConnectivity());
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
    }
  }

  @override
  void didUpdateWidget(covariant HomePremiumMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller?._detach(_handleLocationAction);
    widget.controller?._attach(_handleLocationAction);
  }

  @override
  void dispose() {
    widget.controller?._detach(_handleLocationAction);
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _filterService.filters.removeListener(_onFiltersChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.child == null) {
      _locateUser();
    }
  }

  void _onFiltersChanged() {
    if (mounted) setState(() {});
  }

  void _retry() {
    setState(() {
      _reportsStream = _communityService.watchReports();
    });
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      _updateConnectivity(await _connectivity.checkConnectivity());
    } on Exception {
      // Keep the stream state neutral until connectivity is known.
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final wasDefinitelyOffline = _connectivityKnown && _isDefinitelyOffline;
    final isDefinitelyOffline =
        results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
    setState(() {
      _connectivityKnown = true;
      _isDefinitelyOffline = isDefinitelyOffline;
      if (wasDefinitelyOffline && !isDefinitelyOffline) {
        _reportsStream = _communityService.watchReports();
      }
    });
  }

  Future<void> _openReport(CommunityPost report) => AppNavigator.open<void>(
    context,
    AppDestination.reportDetail,
    arguments: report,
  );

  Future<void> _openCompactSearch() async {
    if (_isSearching) return;

    setState(() => _isSearching = true);
    try {
      final selected = await showSearch<MapSearchResult?>(
        context: context,
        delegate: _MapSearchDelegate(
          searchService: _searchService,
          hintText: context.l10n.mapSearchHint,
          noResultsText: context.l10n.noMapSearchResult,
        ),
      );

      if (selected == null || !mounted) return;
      final explorationCenter = LatLng(selected.latitude, selected.longitude);
      _locationLabelRevision++;
      setState(() {
        _explorationCenter = homeMapExplorationCenterAfterIntent(
          current: _explorationCenter,
          intent: HomeMapCameraIntent.exploration,
          explorationTarget: explorationCenter,
        );
      });
      widget.onLocationLabelChanged?.call(selected.name);
      _submitCameraRequest(
        HomeMapCameraRequest(
          target: explorationCenter,
          zoom: 13.5,
          intent: HomeMapCameraIntent.exploration,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _openMapOptions() async {
    var overlays = _overlays.intersection(_homeLayerOptions.toSet());
    await _showPremiumMapSheet<void>(
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => _HomeMapSheet(
          title: context.l10n.mapLayers,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final overlay in _homeLayerOptions)
                CheckboxListTile(
                  value: overlays.contains(overlay),
                  title: Text(switch (overlay) {
                    MapOverlay.communityReports =>
                      context.l10n.communityReports,
                    MapOverlay.recentCatches => context.l10n.recentCatches,
                  }),
                  onChanged: (value) {
                    setSheetState(() {
                      if (value == true) {
                        overlays.add(overlay);
                      } else {
                        overlays.remove(overlay);
                      }
                    });
                  },
                ),
            ],
          ),
          actions: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton(
                onPressed: () {
                  setState(() {
                    _overlays = Set.unmodifiable(overlays);
                  });
                  Navigator.pop(context);
                },
                child: Text(context.l10n.apply),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<T?> _showPremiumMapSheet<T>({required WidgetBuilder builder}) {
    final width = MediaQuery.sizeOf(context).width;
    final sheetWidth = (width - 16).clamp(0.0, 560.0).toDouble();
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .62),
      constraints: BoxConstraints.tightFor(width: sheetWidth),
      builder: builder,
    );
  }

  Future<void> _locateUser({bool recenter = false}) async {
    if (!mounted) return;
    if (_isLocating) {
      if (recenter) {
        _queuedRecenterLocationRequest = true;
      }
      return;
    }

    final requestRevision = ++_locationRequestRevision;
    final labelRevision = ++_locationLabelRevision;

    setState(() {
      _isLocating = true;
      _locationFailure = null;
    });
    widget.onLocationAvailabilityChanged?.call(
      HomeMapLocationAvailability.locating,
    );
    if (!recenter &&
        _explorationCenter == null &&
        _lastGpsLocationLabel == null) {
      widget.onLocationLabelChanged?.call(null);
    }

    try {
      final languageCode = Localizations.localeOf(context).languageCode;
      final canonical = await ref
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: languageCode, force: recenter);
      if (!mounted || requestRevision != _locationRequestRevision) {
        return;
      }

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
        _lastGpsLocationLabel = deviceLocation.label;
        _locationFailure = null;
      });
      _filterService.setCurrentLocation(
        deviceLocation.latitude,
        deviceLocation.longitude,
      );

      final shouldApplyCamera =
          recenter ||
          shouldApplyAutomaticHomeMapCamera(
            explorationCenter: _explorationCenter,
            didApplyInitialPhysicalCamera: _didApplyInitialUserCamera,
            appliedPhysicalCameraWasCached: _initialUserCameraWasCached,
            resolvedStatus: canonical.status,
          );
      if (shouldApplyCamera) {
        final accepted = _submitCameraRequest(
          HomeMapCameraRequest(
            target: location,
            zoom: recenter ? 13.5 : 12.5,
            intent: recenter
                ? HomeMapCameraIntent.locate
                : HomeMapCameraIntent.automaticLocation,
          ),
        );
        if (accepted) {
          _didApplyInitialUserCamera = true;
          _initialUserCameraWasCached =
              canonical.status == CurrentLocationStatus.cached;
        }
      }

      final locationLabel = deviceLocation.label;
      if (labelRevision == _locationLabelRevision &&
          _explorationCenter == null) {
        widget.onLocationLabelChanged?.call(locationLabel);
      }
      widget.onLocationAvailabilityChanged?.call(
        locationLabel == null
            ? HomeMapLocationAvailability.unavailable
            : HomeMapLocationAvailability.available,
      );
    } on LocationFailure catch (failure) {
      if (mounted) {
        setState(() {
          _locationFailure = failure.reason;
        });
        widget.onLocationAvailabilityChanged?.call(
          HomeMapLocationAvailability.unavailable,
        );
        if (requestRevision == _locationRequestRevision &&
            labelRevision == _locationLabelRevision &&
            _explorationCenter == null) {
          widget.onLocationLabelChanged?.call(_lastGpsLocationLabel);
        }
      }
    } finally {
      if (mounted && requestRevision == _locationRequestRevision) {
        setState(() {
          _isLocating = false;
        });
        if (_queuedRecenterLocationRequest) {
          _queuedRecenterLocationRequest = false;
          _locateUser(recenter: true);
        }
      }
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

  bool _submitCameraRequest(HomeMapCameraRequest request) {
    final mapboxMap = _mapboxMap;
    if (!_isMapReady || mapboxMap == null) {
      final selected = selectPendingHomeMapCameraRequest(
        current: _pendingCameraRequest,
        incoming: request,
      );
      final accepted = identical(selected, request);
      _pendingCameraRequest = selected;
      return accepted;
    }

    _applyCameraRequest(mapboxMap, request);
    _pendingCameraRequest = null;
    return true;
  }

  void _applyCameraRequest(
    mapbox.MapboxMap mapboxMap,
    HomeMapCameraRequest request,
  ) {
    mapboxMap.setCamera(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            request.target.longitude,
            request.target.latitude,
          ),
        ),
        zoom: request.zoom,
      ),
    );
  }

  void _onMapReady(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _isMapReady = true;
    if (!_didApplyInitialUserCamera) {
      _didApplyInitialUserCamera = true;
      _initialUserCameraWasCached = _initialPhysicalCameraWasCached;
    }
    final pending = _pendingCameraRequest;
    _pendingCameraRequest = null;
    if (pending != null) _applyCameraRequest(mapboxMap, pending);
  }

  void _handleLocationAction() {
    _locationLabelRevision++;
    setState(() {
      _explorationCenter = homeMapExplorationCenterAfterIntent(
        current: _explorationCenter,
        intent: HomeMapCameraIntent.locate,
      );
    });
    widget.onLocationLabelChanged?.call(_lastGpsLocationLabel);
    _locateUser(recenter: true);
  }

  String get _locationLabel {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    if (_isLocating) {
      return isRo ? 'Se localizează...' : 'Locating...';
    }

    return switch (_locationFailure) {
      LocationFailureReason.serviceDisabled =>
        isRo ? 'Localizarea este dezactivată' : 'Location is off',
      LocationFailureReason.permissionDenied =>
        isRo ? 'Permisiune refuzată' : 'Permission denied',
      LocationFailureReason.permissionDeniedForever =>
        isRo ? 'Activați din setări' : 'Enable in settings',
      LocationFailureReason.unavailable =>
        isRo ? 'Locație indisponibilă' : 'Location unavailable',
      null => isRo ? 'Locația curentă' : 'Current Location',
    };
  }

  List<CommunityPost> _homeReports(Iterable<CommunityPost> reports) {
    final center = _explorationCenter ?? _currentLocation;
    final showEntireMap = _localRadiusKm.isInfinite;
    if (!showEntireMap && center == null) return const [];

    return reports
        .where((report) {
          final latitude = report.latitude;
          final longitude = report.longitude;
          if (!report.isActiveReport ||
              report.isSuspicious ||
              !_isValidCoordinate(latitude, longitude)) {
            return false;
          }
          if (_reportCategories.isNotEmpty &&
              !_reportCategories.contains(report.reportCategory)) {
            return false;
          }
          return showEntireMap ||
              _isWithinLocalRadius(latitude!, longitude!, center!);
        })
        .toList(growable: false);
  }

  bool _isWithinLocalRadius(
    double latitude,
    double longitude,
    LatLng location,
  ) {
    final distanceMeters = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      latitude,
      longitude,
    );
    return distanceMeters <= _localRadiusKm * 1000;
  }

  static bool _isValidCoordinate(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static String _reportCategoryLabel(
    BuildContext context,
    ReportCategory category,
  ) => switch (category) {
    ReportCategory.fishActivity => context.l10n.reportCategoryFishActivity,
    ReportCategory.waterClarity => context.l10n.reportCategoryWaterClarity,
    ReportCategory.floatingGrass => context.l10n.reportCategoryFloatingGrass,
    ReportCategory.highWater => context.l10n.reportCategoryHighWater,
    ReportCategory.lowWater => context.l10n.reportCategoryLowWater,
    ReportCategory.strongCurrent => context.l10n.reportCategoryStrongCurrent,
    ReportCategory.noCurrent => context.l10n.reportCategoryNoCurrent,
    ReportCategory.boats => context.l10n.reportCategoryBoats,
    ReportCategory.poaching => context.l10n.reportCategoryPoaching,
    ReportCategory.theftWarning => context.l10n.reportCategoryTheftWarning,
    ReportCategory.accessBlocked => context.l10n.reportCategoryAccessBlocked,
    ReportCategory.parkingAvailable =>
      context.l10n.reportCategoryParkingAvailable,
    ReportCategory.goodFishing => context.l10n.reportCategoryGoodFishing,
    ReportCategory.poorFishing => context.l10n.reportCategoryPoorFishing,
    ReportCategory.other => context.l10n.reportCategoryOther,
  };

  Widget _buildMapContent() {
    final customChild = widget.child;
    if (customChild != null) {
      return customChild;
    }

    final initialPhysicalCamera = _initialPhysicalCamera;
    if (initialPhysicalCamera == null) {
      return const _HomeMapStartupLoadingSurface();
    }

    return StreamBuilder<List<CommunityPost>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        final reports = _homeReports(snapshot.data ?? const <CommunityPost>[]);
        final streamState = _connectivityKnown && _isDefinitelyOffline
            ? _HomeReportStreamState.offline
            : snapshot.hasError
            ? _HomeReportStreamState.error
            : snapshot.hasData
            ? _HomeReportStreamState.live
            : _HomeReportStreamState.sync;

        final map = HomeMap(
          reports: reports,
          initialCamera: initialPhysicalCamera,
          onMapTap: widget.onTap,
          onReportTap: _openReport,
          currentLocation: _currentLocation,
          explorationCenter: _explorationCenter,
          onMapboxMapCreated: _onMapReady,
          baseLayer: _baseLayer,
          overlays: _overlays,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: map),
            if (!widget.embedded)
              Positioned(
                right: 12,
                bottom: 8,
                child: _HomeReportStreamBadge(
                  state: streamState,
                  onRetry: streamState == _HomeReportStreamState.error
                      ? _retry
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openFilters() async {
    var draftRadiusKm = _localRadiusKm;
    var draftCategories = {..._reportCategories};
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final localRadiusLabel = isRo ? 'Rază' : 'Local radius';
    final categoriesLabel = isRo
        ? 'Categorii rapoarte comunitare'
        : 'Community report categories';
    final allLabel = isRo ? 'Toate' : 'All';
    final entireMapLabel = isRo ? 'Toată harta' : 'Entire map';

    await _showPremiumMapSheet<void>(
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => _HomeMapSheet(
          title: isRo ? 'Filtre hartă' : 'Map filters',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localRadiusLabel,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<double>(
                isExpanded: true,
                style: const TextStyle(color: Colors.white),
                dropdownColor: _HomeMapSheet._fieldSurface,
                iconEnabledColor: Colors.white70,
                iconDisabledColor: Colors.white38,
                initialValue: draftRadiusKm,
                decoration: InputDecoration(labelText: null),
                items: [
                  const DropdownMenuItem(value: 10, child: Text('10 km')),
                  const DropdownMenuItem(value: 25, child: Text('25 km')),
                  const DropdownMenuItem(value: 50, child: Text('50 km')),
                  const DropdownMenuItem(value: 100, child: Text('100 km')),
                  DropdownMenuItem(
                    value: double.infinity,
                    child: Text(entireMapLabel),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setSheetState(() => draftRadiusKm = value);
                  }
                },
              ),
              const Divider(height: 28),
              Text(
                categoriesLabel,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 6.0;
                  final columns = constraints.maxWidth < 340
                      ? 1
                      : constraints.maxWidth < 520
                      ? 2
                      : 3;
                  final chipWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: 6,
                    children: [
                      SizedBox(
                        width: chipWidth,
                        child: FilterChip(
                          label: Text(allLabel),
                          selected: draftCategories.isEmpty,
                          onSelected: (_) {
                            setSheetState(draftCategories.clear);
                          },
                        ),
                      ),
                      for (final category in ReportCategory.values)
                        SizedBox(
                          width: chipWidth,
                          child: FilterChip(
                            label: Text(
                              _reportCategoryLabel(context, category),
                            ),
                            selected: draftCategories.contains(category),
                            onSelected: (selected) {
                              setSheetState(() {
                                if (selected) {
                                  draftCategories.add(category);
                                } else {
                                  draftCategories.remove(category);
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: Row(
            children: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _localRadiusKm = _defaultLocalRadiusKm;
                    _reportCategories = const {};
                  });
                  Navigator.pop(context);
                },
                child: Text(context.l10n.reset),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _localRadiusKm = draftRadiusKm;
                    _reportCategories = Set<ReportCategory>.unmodifiable(
                      draftCategories,
                    );
                  });
                  Navigator.pop(context);
                },
                child: Text(context.l10n.apply),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canonical = ref.watch(currentLocationProvider);
    final deviceLocation = canonical.location;
    final canonicalCenter = homeMapDeviceCenter(canonical);
    if (canonicalCenter != null && deviceLocation != null) {
      final next = canonicalCenter;
      final initialPhysicalCamera = selectInitialHomeMapPhysicalCamera(
        current: _initialPhysicalCamera,
        canonical: canonical,
      );
      if (_initialPhysicalCamera != initialPhysicalCamera) {
        _initialPhysicalCamera = initialPhysicalCamera;
        _initialPhysicalCameraWasCached =
            canonical.status == CurrentLocationStatus.cached;
      }
      if (_currentLocation != next) {
        _currentLocation = next;
        _lastGpsLocationLabel = deviceLocation.label;
        _locationFailure = null;
        _filterService.setCurrentLocation(
          deviceLocation.latitude,
          deviceLocation.longitude,
        );
      }
    }
    final layout = HomePremiumLayout.of(context);
    final safeInsets = MediaQuery.viewPaddingOf(context);
    final borderRadius = widget.embedded
        ? BorderRadius.zero
        : const BorderRadius.vertical(bottom: Radius.circular(22));
    final horizontalTools =
        widget.embedded ||
        layout.isLandscape ||
        layout.isSmallPhone ||
        layout.heroMapHeight < 280;
    final controlsTop = widget.embedded
        ? 12.0
        : safeInsets.top + (horizontalTools ? 54.0 : 58.0);
    final locationButton = _FloatingButton(
      Icons.my_location_rounded,
      label: _locationLabel,
      onTap: _handleLocationAction,
      isLoading: _isLocating,
      compact: widget.embedded,
    );
    final layersButton = _FloatingButton(
      Icons.layers_rounded,
      label: context.l10n.mapLayers,
      onTap: _openMapOptions,
      compact: widget.embedded,
    );
    final filtersButton = _FloatingButton(
      Icons.filter_alt_rounded,
      label: context.l10n.fishingFilters,
      onTap: _openFilters,
      compact: widget.embedded,
    );
    final tools = horizontalTools
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              locationButton,
              SizedBox(width: widget.embedded ? 5 : 6),
              layersButton,
              SizedBox(width: widget.embedded ? 5 : 6),
              filtersButton,
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              locationButton,
              const SizedBox(height: 6),
              layersButton,
              const SizedBox(height: 6),
              filtersButton,
            ],
          );

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFF16212B)),
          ),
          Positioned.fill(child: _buildMapContent()),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .08),
                  ),
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .34, 1],
                    colors: [
                      Colors.black.withValues(alpha: .55),
                      Colors.transparent,
                      Colors.black.withValues(alpha: .24),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.showControls)
            Positioned(
              left: widget.embedded ? 12 : safeInsets.left + 10,
              top: controlsTop,
              child: _FloatingButton(
                Icons.search_rounded,
                label: context.l10n.mapSearchHint,
                onTap: _openCompactSearch,
                isLoading: _isSearching,
                compact: widget.embedded,
              ),
            ),
          if (widget.showControls)
            Positioned(
              right: widget.embedded ? 12 : safeInsets.right + 10,
              top: controlsTop,
              child: tools,
            ),
        ],
      ),
    );
  }
}

class _HomeMapStartupLoadingSurface extends StatelessWidget {
  const _HomeMapStartupLoadingSurface();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey<String>('home-map-location-loading'),
      color: Color(0xFF16212B),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x1FFFFFFF),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 42,
            child: Icon(
              Icons.my_location_rounded,
              size: 18,
              color: Color(0x99FFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeReportStreamBadge extends StatelessWidget {
  const _HomeReportStreamBadge({required this.state, this.onRetry});

  final _HomeReportStreamState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final (label, icon, background, foreground) = switch (state) {
      _HomeReportStreamState.sync => (
        'SYNC',
        Icons.sync_rounded,
        const Color(0xE62B3742),
        Colors.white70,
      ),
      _HomeReportStreamState.live => (
        'LIVE',
        Icons.sensors_rounded,
        const Color(0xFF67D04B),
        Colors.black,
      ),
      _HomeReportStreamState.offline => (
        'OFFLINE',
        Icons.cloud_off_rounded,
        const Color(0xE62B3742),
        Colors.white70,
      ),
      _HomeReportStreamState.error => (
        isRo ? 'EROARE' : 'ERROR',
        Icons.error_outline_rounded,
        const Color(0xE64A2930),
        const Color(0xFFFFA0A8),
      ),
    };

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: foreground.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: .24),
            blurRadius: 8,
            spreadRadius: -3,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 9,
              letterSpacing: .40,
            ),
          ),
        ],
      ),
    );
    final retry = onRetry;
    if (state != _HomeReportStreamState.error || retry == null) {
      return Semantics(label: label, child: badge);
    }

    return Semantics(
      label: label,
      hint: context.l10n.retryLoadingReports,
      button: true,
      child: Tooltip(
        message: context.l10n.retryLoadingReports,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: retry,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              alignment: Alignment.bottomRight,
              child: badge,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeMapSheet extends StatelessWidget {
  const _HomeMapSheet({
    required this.title,
    required this.content,
    required this.actions,
  });

  static const _background = Color(0xFF0B141D);
  static const _fieldSurface = Color(0xFF111B24);
  static const _accent = Color(0xFF12D8D6);

  final String title;
  final Widget content;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isTablet = media.size.shortestSide >= 600;
    final availableHeight = (media.size.height - media.viewInsets.bottom)
        .clamp(0.0, media.size.height)
        .toDouble();
    final maxHeight =
        availableHeight *
        (isLandscape
            ? .94
            : isTablet
            ? .82
            : .90);
    final baseTheme = Theme.of(context);
    final primaryTextColor = Colors.white.withValues(alpha: .92);
    final secondaryTextColor = Colors.white.withValues(alpha: .70);
    final disabledTextColor = Colors.white.withValues(alpha: .40);
    final colorScheme = baseTheme.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: _accent,
      onPrimary: const Color(0xFF041619),
      surface: _background,
      onSurface: primaryTextColor,
      onSurfaceVariant: secondaryTextColor,
      outline: Colors.white.withValues(alpha: .18),
      outlineVariant: Colors.white.withValues(alpha: .12),
    );
    final sheetTheme = baseTheme.copyWith(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      canvasColor: _background,
      scaffoldBackgroundColor: _background,
      disabledColor: disabledTextColor,
      visualDensity: VisualDensity.compact,
      textTheme: baseTheme.textTheme.apply(
        bodyColor: primaryTextColor,
        displayColor: primaryTextColor,
      ),
      primaryTextTheme: baseTheme.primaryTextTheme.apply(
        bodyColor: primaryTextColor,
        displayColor: primaryTextColor,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: .10),
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _fieldSurface,
        labelStyle: TextStyle(color: secondaryTextColor),
        floatingLabelStyle: const TextStyle(color: _accent),
        hintStyle: TextStyle(color: secondaryTextColor),
        helperStyle: TextStyle(color: disabledTextColor),
        suffixIconColor: secondaryTextColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .10)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.zero,
        textColor: primaryTextColor,
        iconColor: secondaryTextColor,
        selectedColor: _accent,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledTextColor;
          if (states.contains(WidgetState.selected)) return _accent;
          return secondaryTextColor;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledTextColor;
          if (states.contains(WidgetState.selected)) return _accent;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Color(0xFF041619)),
        side: BorderSide(color: secondaryTextColor, width: 1.4),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return disabledTextColor;
          if (states.contains(WidgetState.selected)) return _accent;
          return secondaryTextColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _accent.withValues(alpha: .30);
          }
          return Colors.white.withValues(alpha: .18);
        }),
      ),
      sliderTheme: baseTheme.sliderTheme.copyWith(
        activeTrackColor: _accent,
        inactiveTrackColor: Colors.white.withValues(alpha: .18),
        thumbColor: _accent,
        overlayColor: _accent.withValues(alpha: .14),
        valueIndicatorColor: _fieldSurface,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: _fieldSurface,
        selectedColor: _accent.withValues(alpha: .22),
        disabledColor: Colors.white.withValues(alpha: .04),
        checkmarkColor: _accent,
        labelStyle: TextStyle(color: primaryTextColor),
        secondaryLabelStyle: TextStyle(color: primaryTextColor),
        side: BorderSide(color: Colors.white.withValues(alpha: .18)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: const Color(0xFF041619),
          minimumSize: const Size(96, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: .78),
          minimumSize: const Size(88, 44),
        ),
      ),
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Theme(
            data: sheetTheme,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .38),
                    blurRadius: 28,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 8),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .28),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: .10),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: content,
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: .10),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: actions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapSearchDelegate extends SearchDelegate<MapSearchResult?> {
  _MapSearchDelegate({
    required this.searchService,
    required String hintText,
    required this.noResultsText,
  }) : super(searchFieldLabel: hintText);

  final MapSearchService searchService;
  final String noResultsText;

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
          onPressed: () => query = '',
          icon: const Icon(Icons.clear_rounded),
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<MapSearchResult>>(
      future: searchService.search(trimmed),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data ?? const <MapSearchResult>[];
        if (results.isEmpty) return Center(child: Text(noResultsText));
        return _buildSearchResults(results);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return buildSuggestions(context);

    return FutureBuilder<List<MapSearchResult>>(
      future: searchService.search(trimmed),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data ?? const <MapSearchResult>[];
        if (results.isEmpty) {
          return Center(child: Text(noResultsText));
        }
        return _buildSearchResults(results);
      },
    );
  }

  Widget _buildSearchResults(Iterable<MapSearchResult> results) {
    final items = results.toList(growable: false);
    if (items.isEmpty) return Center(child: Text(noResultsText));
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = items[index];
        return ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(result.name),
          subtitle: result.description == null
              ? null
              : Text(result.description!),
          onTap: () => close(context, result),
        );
      },
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    required this.borderRadius,
    required this.blur,
  });

  final Widget child;
  final double borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF101720).withValues(alpha: .58),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: Colors.white.withValues(alpha: .13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _FloatingButton extends StatelessWidget {
  const _FloatingButton(
    this.icon, {
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 14.0 : 17.0;
    final dimension = compact ? 42.0 : 48.0;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: _GlassSurface(
          borderRadius: radius,
          blur: 22,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox.square(
                dimension: dimension,
                child: Center(
                  child: isLoading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          icon,
                          color: Colors.white.withValues(alpha: .92),
                          size: compact ? 17 : 18,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
