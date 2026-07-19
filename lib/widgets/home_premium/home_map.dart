import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../services/community_service.dart';
import '../../services/favorite_stations_service.dart';
import '../../services/location_service.dart';
import '../../services/map_search_service.dart';
import '../../services/station_filter_service.dart';
import '../../services/water_service.dart';
import '../../screens/community_details_page.dart';
import '../../screens/station_details_page.dart';
import 'home_premium_layout.dart';
import '../home/home_map.dart';

enum HomeMapLocationAvailability { locating, available, unavailable }

enum _HomeReportStreamState { sync, live, offline }

class HomePremiumMap extends StatefulWidget {
  const HomePremiumMap({
    super.key,
    this.onTap,
    this.child,
    this.showWaterStations = false,
    this.onLocationAvailabilityChanged,
    this.onLocationLabelChanged,
  });

  final VoidCallback? onTap;
  final Widget? child;
  final bool showWaterStations;
  final ValueChanged<HomeMapLocationAvailability>?
  onLocationAvailabilityChanged;
  final ValueChanged<String?>? onLocationLabelChanged;

  @override
  State<HomePremiumMap> createState() => _HomePremiumMapState();
}

class _HomePremiumMapState extends State<HomePremiumMap> {
  static const _defaultLocalRadiusKm = 100.0;
  static const _homeLayerOptions = <MapOverlay>[
    MapOverlay.waterStations,
    MapOverlay.communityReports,
    MapOverlay.favoriteStations,
  ];

  final CommunityService _communityService = const CommunityService();
  final LocationService _locationService = const LocationService();
  final MapSearchService _searchService = const MapSearchService();
  final WaterService _waterService = WaterService();
  final FavoriteStationsService _favoriteStationsService =
      const FavoriteStationsService();
  mapbox.MapboxMap? _mapboxMap;
  final StationFilterService _filterService = StationFilterService.instance;
  late Stream<List<CommunityPost>> _reportsStream;
  List<Station> _stations = const [];
  Set<String> _favoriteStationIds = const {};
  Set<ReportCategory> _reportCategories = const {};
  LatLng? _explorationCenter;
  double _localRadiusKm = _defaultLocalRadiusKm;
  LatLng? _currentLocation;
  LocationFailureReason? _locationFailure;
  bool _isLocating = false;
  bool _isMapReady = false;
  bool _pendingRecenter = false;
  bool _didApplyInitialUserCamera = false;
  LatLng? _pendingCameraTarget;
  double _pendingCameraZoom = 13.5;
  bool _isSearching = false;
  final MapBaseLayer _baseLayer = MapBaseLayer.standard;
  Set<MapOverlay> _overlays = const {MapOverlay.communityReports};

  @override
  void initState() {
    super.initState();
    _reportsStream = _communityService.watchReports();
    _filterService.filters.addListener(_onFiltersChanged);
    FavoriteStationsService.revision.addListener(_loadFavoriteIds);
    if (widget.child == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
    }
    if (widget.child == null || widget.showWaterStations) {
      _loadStations();
    }
  }

  @override
  void dispose() {
    _filterService.filters.removeListener(_onFiltersChanged);
    FavoriteStationsService.revision.removeListener(_loadFavoriteIds);
    super.dispose();
  }

  void _onFiltersChanged() {
    if (mounted) setState(() {});
  }

  void _retry() {
    setState(() {
      _reportsStream = _communityService.watchReports();
    });
  }

  Future<void> _loadStations() async {
    try {
      final stations = await _waterService.getStations();
      if (mounted) setState(() => _stations = stations);
    } on Exception {
      // The base map remains usable when station data is unavailable.
    }
    await _loadFavoriteIds();
  }

  Future<void> _loadFavoriteIds() async {
    if (!_favoriteStationsService.isAuthenticated) {
      if (mounted) setState(() => _favoriteStationIds = const {});
      return;
    }
    try {
      final ids = await _favoriteStationsService.getFavoriteIds();
      if (mounted) setState(() => _favoriteStationIds = ids);
    } on FavoriteException {
      // Other map layers remain available if favourites cannot be loaded.
    }
  }

  Future<void> _openStation(Station station) async {
    _waterService.selectStation(station);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StationDetailsPage(station: station),
      ),
    );
    await _loadFavoriteIds();
  }

  Future<void> _openReport(CommunityPost report) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => CatchDetailsPage(post: report),
      ),
    );
  }

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
      setState(() => _explorationCenter = explorationCenter);
      _moveCamera(explorationCenter, zoom: 13.5);
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
                    MapOverlay.waterStations => context.l10n.waterStations,
                    MapOverlay.communityReports =>
                      context.l10n.communityReports,
                    MapOverlay.recentCatches => context.l10n.recentCatches,
                    MapOverlay.favoriteStations =>
                      context.l10n.favoriteStations,
                  }),
                  onChanged: (value) {
                    if (overlay == MapOverlay.favoriteStations &&
                        value == true &&
                        !_favoriteStationsService.isAuthenticated) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.signInForFavoriteStations),
                        ),
                      );
                      return;
                    }
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
    if (_isLocating) {
      return;
    }

    final knownLocation = _currentLocation;
    if (knownLocation != null && recenter) {
      _recenter(knownLocation);
      return;
    }

    setState(() {
      _isLocating = true;
      _locationFailure = null;
      _pendingRecenter = recenter;
    });
    widget.onLocationAvailabilityChanged?.call(
      HomeMapLocationAvailability.locating,
    );
    widget.onLocationLabelChanged?.call(null);

    try {
      final position = await _locationService.determinePosition();
      if (!mounted) {
        return;
      }

      final location = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = location;
        _locationFailure = null;
      });
      _filterService.setCurrentLocation(position.latitude, position.longitude);

      if (_pendingRecenter || recenter || !_didApplyInitialUserCamera) {
        _didApplyInitialUserCamera = true;
        _moveCamera(location, zoom: recenter || _pendingRecenter ? 13.5 : 12.5);
      }

      final languageCode = Localizations.localeOf(context).languageCode;
      final locationLabel = await _locationService.resolveLocalityRegion(
        position,
        languageCode: languageCode,
      );
      if (!mounted) return;
      widget.onLocationLabelChanged?.call(locationLabel);
      widget.onLocationAvailabilityChanged?.call(
        locationLabel == null
            ? HomeMapLocationAvailability.unavailable
            : HomeMapLocationAvailability.available,
      );
    } on LocationFailure catch (failure) {
      if (mounted) {
        setState(() {
          _locationFailure = failure.reason;
          _pendingRecenter = false;
        });
        widget.onLocationAvailabilityChanged?.call(
          HomeMapLocationAvailability.unavailable,
        );
        widget.onLocationLabelChanged?.call(null);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _recenter(LatLng location) {
    _moveCamera(location, zoom: 13.5);
  }

  void _moveCamera(LatLng target, {required double zoom}) {
    final mapboxMap = _mapboxMap;
    if (!_isMapReady || mapboxMap == null) {
      _pendingCameraTarget = target;
      _pendingCameraZoom = zoom;
      _pendingRecenter = true;
      return;
    }

    mapboxMap.setCamera(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(target.longitude, target.latitude),
        ),
        zoom: zoom,
      ),
    );
    _pendingCameraTarget = null;
    _pendingRecenter = false;
  }

  void _onMapReady(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _isMapReady = true;
    final pendingTarget = _pendingCameraTarget;
    if (pendingTarget != null) {
      _moveCamera(pendingTarget, zoom: _pendingCameraZoom);
      return;
    }

    final location = _currentLocation;
    if (_pendingRecenter && location != null) {
      _recenter(location);
    }
  }

  void _handleLocationAction() {
    if (_explorationCenter != null) {
      setState(() => _explorationCenter = null);
    }
    final location = _currentLocation;
    if (location != null) {
      _recenter(location);
      return;
    }

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

  List<Station> _homeStations() {
    final showWaterStations = _overlays.contains(MapOverlay.waterStations);
    final showFavoriteStations = _overlays.contains(
      MapOverlay.favoriteStations,
    );
    if (!showWaterStations && !showFavoriteStations) return const [];

    final uniqueStations = <String, Station>{};
    for (final station in _stations) {
      if (showWaterStations || _favoriteStationIds.contains(station.id)) {
        uniqueStations.putIfAbsent(station.id, () => station);
      }
    }
    return List<Station>.unmodifiable(uniqueStations.values);
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

    return StreamBuilder<List<CommunityPost>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        final reports = _homeReports(snapshot.data ?? const <CommunityPost>[]);
        final streamState = snapshot.hasError
            ? _HomeReportStreamState.offline
            : snapshot.hasData
            ? _HomeReportStreamState.live
            : _HomeReportStreamState.sync;

        final map = HomeMap(
          reports: reports,
          stations: _homeStations(),
          favoriteStationIds: _favoriteStationIds,
          onReportTap: _openReport,
          onStationTap: _openStation,
          currentLocation: _currentLocation,
          onMapboxMapCreated: _onMapReady,
          baseLayer: _baseLayer,
          overlays: _overlays,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: map),
            Positioned(
              right: 12,
              bottom: 10,
              child: _HomeReportStreamBadge(
                state: streamState,
                onRetry: streamState == _HomeReportStreamState.offline
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
    const borderRadius = 28.0;
    final layout = HomePremiumLayout.of(context);
    final mapHeight = layout.heroMapHeight.clamp(315.0, 390.0).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 1, 2, 1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .42),
              blurRadius: 30,
              spreadRadius: -8,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: const Color(0xFF2B7FFF).withValues(alpha: .08),
              blurRadius: 22,
              spreadRadius: -10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          height: mapHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFF16212B)),
                ),

                // Map content fills the whole allocated card while the outer
                // frame keeps the premium rounded shape.
                Positioned.fill(child: _buildMapContent()),

                // Decorative frame above the map.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(borderRadius),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .09),
                          ),
                          borderRadius: BorderRadius.circular(borderRadius),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0, .38, 1],
                            colors: [
                              Colors.black.withValues(alpha: .10),
                              Colors.transparent,
                              Colors.black.withValues(alpha: .38),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // SEARCH - icon only, small and premium.
                Positioned(
                  left: 10,
                  top: 44,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openCompactSearch,
                    child: _GlassSurface(
                      borderRadius: 15,
                      blur: 16,
                      child: SizedBox.square(
                        dimension: 38,
                        child: Center(
                          child: _isSearching
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF67D04B),
                                  ),
                                )
                              : const Icon(
                                  Icons.search_rounded,
                                  size: 21,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Floating tools stay compact and do not reduce map height.
                Positioned(
                  right: 12,
                  top: 44,
                  child: Column(
                    children: [
                      Semantics(
                        label: _locationLabel,
                        button: true,
                        child: _FloatingButton(
                          Icons.my_location_rounded,
                          onTap: _handleLocationAction,
                          isLoading: _isLocating,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _FloatingButton(
                        Icons.layers_rounded,
                        onTap: _openMapOptions,
                      ),
                      const SizedBox(height: 6),
                      _FloatingButton(
                        Icons.filter_alt_rounded,
                        onTap: _openFilters,
                      ),
                    ],
                  ),
                ),
              ],
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
          Icon(icon, size: 9, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: 7.8,
              letterSpacing: .40,
            ),
          ),
        ],
      ),
    );
    final retry = onRetry;
    if (state != _HomeReportStreamState.offline || retry == null) {
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
          child: SizedBox(
            width: 48,
            height: 48,
            child: Align(alignment: Alignment.bottomRight, child: badge),
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
  const _FloatingButton(this.icon, {this.onTap, this.isLoading = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _GlassSurface(
      borderRadius: 17,
      blur: 22,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: SizedBox(
            width: 40,
            height: 40,
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
                      size: 18,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
