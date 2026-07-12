import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:latlong2/latlong.dart';

import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../services/community_service.dart';
import '../../services/build_mode_service.dart';
import '../../services/favorite_stations_service.dart';
import '../../services/location_service.dart';
import '../../services/map_search_service.dart';
import '../../services/station_filter_service.dart';
import '../../services/water_service.dart';
import '../../screens/station_details_page.dart';
import '../../core/theme/app_dimensions.dart';
import 'home_premium_layout.dart';
import '../home/home_map.dart';

class HomePremiumMap extends StatefulWidget {
  const HomePremiumMap({
    super.key,
    this.onTap,
    this.child,
    this.showWaterStations = false,
  });

  final VoidCallback? onTap;
  final Widget? child;
  final bool showWaterStations;

  @override
  State<HomePremiumMap> createState() => _HomePremiumMapState();
}

class _HomePremiumMapState extends State<HomePremiumMap> {
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
  List<CommunityPost> _recentCatches = const [];
  Set<String> _favoriteStationIds = const {};
  LatLng? _currentLocation;
  LocationFailureReason? _locationFailure;
  bool _isLocating = false;
  bool _isMapReady = false;
  bool _pendingRecenter = false;
  bool _didApplyInitialUserCamera = false;
  LatLng? _pendingCameraTarget;
  double _pendingCameraZoom = 13.5;
  bool _isSearching = false;
  MapBaseLayer _baseLayer = MapBaseLayer.standard;
  Set<MapOverlay> _overlays = const {
    MapOverlay.waterStations,
    MapOverlay.communityReports,
  };

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
    await Future.wait([_loadFavoriteIds(), _loadRecentCatches()]);
  }
  Future<List<Station>> _ensureStationsLoaded() async {
    if (_stations.isNotEmpty) return _stations;

    try {
      final stations = await _waterService.getStations();
      if (mounted) setState(() => _stations = stations);
      return stations;
    } on Exception {
      return _stations;
    }
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

  Future<void> _loadRecentCatches() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 72));
      final posts = await _communityService.getFeed();
      final catches = posts
          .where((post) => post.type == CommunityPostType.catchPost)
          .where((post) => post.createdAt.isAfter(cutoff))
          .toList(growable: false);
      if (mounted) setState(() => _recentCatches = catches);
    } on CommunityException {
      // Reports and station markers remain usable without recent catches.
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

  Future<void> _openCompactSearch() async {
    if (_isSearching) return;

    setState(() => _isSearching = true);
    try {
      final stations = await _ensureStationsLoaded();
      if (!mounted) return;

      final selected = await showSearch<MapSearchResult?>(
        context: context,
        delegate: _MapSearchDelegate(
          searchService: _searchService,
          stations: stations,
          hintText: context.l10n.mapSearchHint,
          noResultsText: context.l10n.noMapSearchResult,
        ),
      );

      if (selected == null || !mounted) return;
      _filterService.updateQuery(selected.name);
      _moveCamera(
        LatLng(selected.latitude, selected.longitude),
        zoom: 13.5,
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _openMapOptions() async {
    var layer = _baseLayer;
    var overlays = {..._overlays};
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.mapLayers,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                RadioGroup<MapBaseLayer>(
                  groupValue: layer,
                  onChanged: (value) {
                    if (value != null) setSheetState(() => layer = value);
                  },
                  child: Column(
                    children: [
                      RadioListTile(
                        value: MapBaseLayer.standard,
                        title: Text(context.l10n.standard),
                      ),
                      if (BuildModeService.isDeveloperVisible) ...[
                        RadioListTile(
                          value: MapBaseLayer.satellite,
                          enabled: false,
                          title: Text(context.l10n.satellite),
                          subtitle: Text(context.l10n.comingSoon),
                        ),
                        RadioListTile(
                          value: MapBaseLayer.fishingMode,
                          enabled: false,
                          title: Text(context.l10n.fishingMode),
                          subtitle: Text(context.l10n.comingSoon),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(),
                for (final overlay in MapOverlay.values)
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
                            content: Text(
                              context.l10n.signInForFavoriteStations,
                            ),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _baseLayer = layer;
                        _overlays = Set.unmodifiable(overlays);
                      });
                      Navigator.pop(context);
                    },
                    child: Text(context.l10n.apply),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        _moveCamera(
          location,
          zoom: recenter || _pendingRecenter ? 13.5 : 12.5,
        );
      }
    } on LocationFailure catch (failure) {
      if (mounted) {
        setState(() {
          _locationFailure = failure.reason;
          _pendingRecenter = false;
        });
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

  static String _localizedTrendName(BuildContext context, String value) {
    if (Localizations.localeOf(context).languageCode != 'ro') return value;
    return switch (value.trim().toLowerCase()) {
      'rising' => 'În creștere',
      'stable' => 'Stabil',
      'falling' => 'În scădere',
      _ => value,
    };
  }

  Widget _buildMapContent() {
    final customChild = widget.child;
    if (customChild != null) {
      return customChild;
    }

    return StreamBuilder<List<CommunityPost>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        final reports = (snapshot.data ?? const <CommunityPost>[])
            .where((report) => report.isActiveReport)
            .toList(growable: false);

        final map = HomeMap(
          reports: reports,
          stations: _filterService.apply(_stations),
          recentCatches: _recentCatches,
          favoriteStationIds: _favoriteStationIds,
          onStationTap: _openStation,
          currentLocation: _currentLocation,
          onMapboxMapCreated: _onMapReady,
          baseLayer: _baseLayer,
          overlays: _overlays,
        );

        final isLoading = !snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: map),
            if (isLoading)
              Positioned(
                left: 62,
                top: 12,
                child: _GlassSurface(
                  borderRadius: 14,
                  blur: 14,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox.square(
                          dimension: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Color(0xFF67D04B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          Localizations.localeOf(context).languageCode == 'ro'
                              ? 'Date în timp real'
                              : 'Live data',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (snapshot.hasError)
              Positioned(
                right: 12,
                bottom: 54,
                child: _GlassSurface(
                  borderRadius: 16,
                  blur: 16,
                  child: IconButton(
                    tooltip: context.l10n.retryLoadingReports,
                    onPressed: _retry,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Kept temporarily for compatibility while fishing filters move to overlays.
  // ignore: unused_element
  Future<void> _openFilters() async {
    var draft = _filterService.filters.value;
    var levelRange = RangeValues(
      draft.minimumWaterLevel ?? 0,
      draft.maximumWaterLevel ?? 1000,
    );
    var filterLevel =
        draft.minimumWaterLevel != null || draft.maximumWaterLevel != null;
    final species = <String>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.fishingFilters,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                DropdownButtonFormField<WaterBodyType?>(
                  initialValue: draft.waterBodyType,
                  decoration: InputDecoration(
                    labelText: context.l10n.waterType,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.l10n.riverAndLake),
                    ),
                    DropdownMenuItem(
                      value: WaterBodyType.river,
                      child: Text(context.l10n.river),
                    ),
                    DropdownMenuItem(
                      value: WaterBodyType.lake,
                      child: Text(context.l10n.lake),
                    ),
                  ],
                  onChanged: (value) => setSheetState(
                    () => draft = StationFilters(
                      query: draft.query,
                      waterBodyType: value,
                      species: draft.species,
                      radiusKm: draft.radiusKm,
                      minimumWaterLevel: draft.minimumWaterLevel,
                      maximumWaterLevel: draft.maximumWaterLevel,
                      trends: draft.trends,
                      difficulty: draft.difficulty,
                      favoritesOnly: draft.favoritesOnly,
                    ),
                  ),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: draft.species,
                  decoration: InputDecoration(labelText: context.l10n.species),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.l10n.allSpecies),
                    ),
                    ...species.map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    ),
                  ],
                  onChanged: (value) => setSheetState(
                    () => draft = StationFilters(
                      query: draft.query,
                      waterBodyType: draft.waterBodyType,
                      species: value,
                      radiusKm: draft.radiusKm,
                      minimumWaterLevel: draft.minimumWaterLevel,
                      maximumWaterLevel: draft.maximumWaterLevel,
                      trends: draft.trends,
                      difficulty: draft.difficulty,
                      favoritesOnly: draft.favoritesOnly,
                    ),
                  ),
                ),
                DropdownButtonFormField<double?>(
                  initialValue: draft.radiusKm,
                  decoration: InputDecoration(
                    labelText: context.l10n.gpsRadius,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.l10n.anyDistance),
                    ),
                    DropdownMenuItem(value: 10, child: Text('10 km')),
                    DropdownMenuItem(value: 25, child: Text('25 km')),
                    DropdownMenuItem(value: 50, child: Text('50 km')),
                    DropdownMenuItem(value: 100, child: Text('100 km')),
                  ],
                  onChanged: (value) => setSheetState(
                    () => draft = StationFilters(
                      query: draft.query,
                      waterBodyType: draft.waterBodyType,
                      species: draft.species,
                      radiusKm: value,
                      minimumWaterLevel: draft.minimumWaterLevel,
                      maximumWaterLevel: draft.maximumWaterLevel,
                      trends: draft.trends,
                      difficulty: draft.difficulty,
                      favoritesOnly: draft.favoritesOnly,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.filterByWaterLevel),
                  value: filterLevel,
                  onChanged: (value) =>
                      setSheetState(() => filterLevel = value),
                ),
                if (filterLevel)
                  RangeSlider(
                    values: levelRange,
                    max: 1000,
                    divisions: 100,
                    labels: RangeLabels(
                      '${levelRange.start.round()} cm',
                      '${levelRange.end.round()} cm',
                    ),
                    onChanged: (value) =>
                        setSheetState(() => levelRange = value),
                  ),
                Text(context.l10n.waterTrend),
                Wrap(
                  spacing: 6,
                  children: WaterTrend.values.map((trend) {
                    return FilterChip(
                      label: Text(_localizedTrendName(context, trend.name)),
                      selected: draft.trends.contains(trend),
                      onSelected: (selected) {
                        setSheetState(() {
                          final trends = {...draft.trends};
                          if (selected) {
                            trends.add(trend);
                          } else {
                            trends.remove(trend);
                          }
                          draft = StationFilters(
                            query: draft.query,
                            waterBodyType: draft.waterBodyType,
                            species: draft.species,
                            radiusKm: draft.radiusKm,
                            minimumWaterLevel: draft.minimumWaterLevel,
                            maximumWaterLevel: draft.maximumWaterLevel,
                            trends: trends,
                            difficulty: draft.difficulty,
                            favoritesOnly: draft.favoritesOnly,
                          );
                        });
                      },
                    );
                  }).toList(),
                ),
                DropdownButtonFormField<FishingDifficulty?>(
                  initialValue: draft.difficulty,
                  decoration: InputDecoration(
                    labelText: context.l10n.difficulty,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(context.l10n.anyDifficulty),
                    ),
                    DropdownMenuItem(
                      value: FishingDifficulty.easy,
                      child: Text(context.l10n.easy),
                    ),
                    DropdownMenuItem(
                      value: FishingDifficulty.moderate,
                      child: Text(context.l10n.moderate),
                    ),
                    DropdownMenuItem(
                      value: FishingDifficulty.hard,
                      child: Text(context.l10n.hard),
                    ),
                  ],
                  onChanged: (value) => setSheetState(
                    () => draft = StationFilters(
                      query: draft.query,
                      waterBodyType: draft.waterBodyType,
                      species: draft.species,
                      radiusKm: draft.radiusKm,
                      minimumWaterLevel: draft.minimumWaterLevel,
                      maximumWaterLevel: draft.maximumWaterLevel,
                      trends: draft.trends,
                      difficulty: value,
                      favoritesOnly: draft.favoritesOnly,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.favoritesOnly),
                  value: draft.favoritesOnly,
                  onChanged: (value) => setSheetState(
                    () => draft = StationFilters(
                      query: draft.query,
                      waterBodyType: draft.waterBodyType,
                      species: draft.species,
                      radiusKm: draft.radiusKm,
                      minimumWaterLevel: draft.minimumWaterLevel,
                      maximumWaterLevel: draft.maximumWaterLevel,
                      trends: draft.trends,
                      difficulty: draft.difficulty,
                      favoritesOnly: value,
                    ),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        _filterService.update(
                          StationFilters(query: draft.query),
                        );
                        Navigator.pop(context);
                      },
                      child: Text(context.l10n.reset),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        _filterService.update(
                          StationFilters(
                            query: draft.query,
                            waterBodyType: draft.waterBodyType,
                            species: draft.species,
                            radiusKm: draft.radiusKm,
                            minimumWaterLevel: filterLevel
                                ? levelRange.start
                                : null,
                            maximumWaterLevel: filterLevel
                                ? levelRange.end
                                : null,
                            trends: draft.trends,
                            difficulty: draft.difficulty,
                            favoritesOnly: draft.favoritesOnly,
                          ),
                        );
                        Navigator.pop(context);
                      },
                      child: Text(context.l10n.apply),
                    ),
                  ],
                ),
              ],
            ),
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
      padding: EdgeInsets.fromLTRB(
        AppDimensions.sectionSpacing,
        8,
        AppDimensions.sectionSpacing,
        10,
      ),
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
                      dimension: 40,
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
                                size: 23,
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
                    _FloatingButton(
                      Icons.my_location_rounded,
                      onTap: _handleLocationAction,
                      isLoading: _isLocating,
                    ),
                    const SizedBox(height: 8),
                    _FloatingButton(Icons.layers_rounded, onTap: _openMapOptions),
                    const SizedBox(height: 8),
                    _FloatingButton(
                      Icons.filter_alt_rounded,
                      onTap: _openMapOptions,
                    ),
                  ],
                ),
              ),

              // LOCATION - compact overlay over the map, not separate layout space.
              Positioned(
                left: 10,
                bottom: 36,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleLocationAction,
                  child: _GlassSurface(
                    borderRadius: 14,
                    blur: 18,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isLocating)
                            const SizedBox.square(
                              dimension: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: Color(0xFF67D04B),
                              ),
                            )
                          else
                            const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFF67D04B),
                              size: 14,
                            ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 118),
                            child: Text(
                              _locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 10.5,
                                letterSpacing: .05,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // LIVE - small premium badge over the map.
              Positioned(
                right: 12,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF67D04B),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF67D04B).withValues(alpha: .24),
                        blurRadius: 8,
                        spreadRadius: -3,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sensors_rounded,
                        size: 10,
                        color: Colors.black,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 8.5,
                          letterSpacing: .45,
                        ),
                      ),
                    ],
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
}

class _MapSearchDelegate extends SearchDelegate<MapSearchResult?> {
  _MapSearchDelegate({
    required this.searchService,
    required this.stations,
    required String hintText,
    required this.noResultsText,
  }) : super(searchFieldLabel: hintText);

  final MapSearchService searchService;
  final List<Station> stations;
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
    if (trimmed.isEmpty) {
      return _buildStationSuggestions(stations.take(12).map(_stationResult));
    }

    return FutureBuilder<List<MapSearchResult>>(
      future: _combinedResults(trimmed),
      builder: (context, snapshot) {
        final stationFallback =
            searchService.searchStations(trimmed, stations).take(12);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildStationSuggestions(stationFallback);
        }

        final results = snapshot.data ?? stationFallback.toList(growable: false);
        if (results.isEmpty) return Center(child: Text(noResultsText));
        return _buildStationSuggestions(results.take(12));
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return buildSuggestions(context);

    return FutureBuilder<List<MapSearchResult>>(
      future: _combinedResults(trimmed),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data ?? const <MapSearchResult>[];
        if (results.isEmpty) {
          return Center(child: Text(noResultsText));
        }
        return _buildStationSuggestions(results);
      },
    );
  }

  Widget _buildStationSuggestions(Iterable<MapSearchResult> results) {
    final items = results.toList(growable: false);
    if (items.isEmpty) return Center(child: Text(noResultsText));
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = items[index];
        return ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(result.name),
          subtitle: result.description == null ? null : Text(result.description!),
          onTap: () => close(context, result),
        );
      },
    );
  }

  Future<List<MapSearchResult>> _combinedResults(String value) async {
    final stationResults = searchService.searchStations(value, stations);
    final remoteResults = await searchService.search(value);
    final seen = <String>{};
    final merged = <MapSearchResult>[];
    for (final result in [...stationResults, ...remoteResults]) {
      final key =
          '${result.name.toLowerCase()}|${result.latitude.toStringAsFixed(4)}|${result.longitude.toStringAsFixed(4)}';
      if (seen.add(key)) merged.add(result);
    }
    return merged;
  }

  static MapSearchResult _stationResult(Station station) {
    return MapSearchResult(
      name: station.name,
      description: station.river.isEmpty ? null : station.river,
      latitude: station.latitude,
      longitude: station.longitude,
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
            width: 50,
            height: 50,
            child: Center(
              child: isLoading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      icon,
                      color: Colors.white.withValues(alpha: .92),
                      size: 22,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
