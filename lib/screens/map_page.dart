import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../l10n/l10n.dart';
import '../models/station.dart';
import '../services/community_service.dart';
import '../services/location_service.dart';
import '../services/map_search_service.dart';
import '../services/water_service.dart';
import 'station_details_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.onAddCatch,
    required this.onCreateReport,
    required this.onOpenFavorites,
  });

  final VoidCallback onAddCatch;
  final ValueChanged<ReportCategory> onCreateReport;
  final VoidCallback onOpenFavorites;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const _satelliteStreetsStyle =
      'mapbox://styles/mapbox/satellite-streets-v12';
  static const _fallbackCamera = LatLng(44.8148, 21.3895);

  final LocationService _locationService = const LocationService();
  final MapSearchService _searchService = const MapSearchService();
  final WaterService _waterService = WaterService();

  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _stationAnnotationManager;
  mapbox.CircleAnnotationManager? _stationHighlightAnnotationManager;
  mapbox.CircleAnnotationManager? _userAnnotationManager;
  dynamic _stationTapEvents;

  List<Station> _stations = const [];
  LatLng? _currentLocation;
  LatLng? _pendingCameraTarget;
  double _pendingCameraZoom = 13.5;
  bool _isMapReady = false;
  bool _isLocating = false;
  bool _isLoadingStations = false;
  bool _actionsExpanded = false;
  bool _stationLayerVisible = true;
  Station? _temporarilyHighlightedStation;
  String? _stationLoadError;
  Orientation? _orientation;
  Size? _mediaSize;

  @override
  void initState() {
    super.initState();
    _loadStations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    final mediaSize = MediaQuery.sizeOf(context);
    if (_orientation == orientation && _mediaSize == mediaSize) return;
    if (_orientation != null && _orientation != orientation) {
      _actionsExpanded = false;
    }
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
    _stationTapEvents?.cancel();
    _stationAnnotationManager?.deleteAll();
    _stationHighlightAnnotationManager?.deleteAll();
    _userAnnotationManager?.deleteAll();
    super.dispose();
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _isMapReady = true;

    await _updateMapboxOrnaments(mapboxMap);

    _stationAnnotationManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    _stationTapEvents = _stationAnnotationManager?.tapEvents(
      onTap: _handleStationAnnotationTap,
    );
    _stationHighlightAnnotationManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    _userAnnotationManager =
        await mapboxMap.annotations.createCircleAnnotationManager();

    await _syncStationAnnotations();
    await _syncUserAnnotation();

    final pendingTarget = _pendingCameraTarget;
    if (pendingTarget != null) {
      _moveCamera(pendingTarget, zoom: _pendingCameraZoom);
      return;
    }

    final location = _currentLocation;
    if (location != null) {
      _moveCamera(location, zoom: 12.5);
    }
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
      await _syncStationAnnotations();
    } on Exception {
      if (!mounted) return;
      setState(() => _stationLoadError = context.l10n.waterProviderUnavailable);
    } finally {
      if (mounted) setState(() => _isLoadingStations = false);
    }
  }

  Future<void> _locateUser({bool recenter = false}) async {
    if (_isLocating) return;

    final knownLocation = _currentLocation;
    if (knownLocation != null && recenter) {
      _moveCamera(knownLocation, zoom: 13.5);
      return;
    }

    setState(() => _isLocating = true);
    try {
      final position = await _locationService.determinePosition();
      if (!mounted) return;
      final location = LatLng(position.latitude, position.longitude);
      setState(() => _currentLocation = location);
      await _syncUserAnnotation();
      _moveCamera(location, zoom: recenter ? 13.5 : 12.5);
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      final message = switch (failure.reason) {
        LocationFailureReason.serviceDisabled => context.l10n.locationRequired,
        LocationFailureReason.permissionDenied => context.l10n.locationRequired,
        LocationFailureReason.permissionDeniedForever =>
          context.l10n.locationRequired,
        LocationFailureReason.unavailable => context.l10n.notAvailable,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _moveCamera(LatLng target, {required double zoom}) {
    final mapboxMap = _mapboxMap;
    if (!_isMapReady || mapboxMap == null) {
      _pendingCameraTarget = target;
      _pendingCameraZoom = zoom;
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
  }

  Future<void> _syncStationAnnotations() async {
    final manager = _stationAnnotationManager;
    final highlightManager = _stationHighlightAnnotationManager;
    if (!_isMapReady || manager == null || highlightManager == null) return;

    final existingAnnotations = await manager.getAnnotations();
    if (existingAnnotations.length != _stations.length) {
      await manager.deleteAll();
      if (_stations.isNotEmpty) {
        final annotations = _stations
            .map(_stationAnnotationOptions)
            .toList(growable: false);
        await manager.createMulti(annotations);
      }
    }

    await manager.setCircleOpacity(_stationLayerVisible ? .92 : 0);
    await manager.setCircleStrokeOpacity(_stationLayerVisible ? 1 : 0);

    await highlightManager.deleteAll();
    final highlightedStation = _temporarilyHighlightedStation;
    if (!_stationLayerVisible && highlightedStation != null) {
      await highlightManager.create(
        _stationAnnotationOptions(highlightedStation, highlighted: true),
      );
    }
  }

  mapbox.CircleAnnotationOptions _stationAnnotationOptions(
    Station station, {
    bool highlighted = false,
  }) => mapbox.CircleAnnotationOptions(
    geometry: mapbox.Point(
      coordinates: mapbox.Position(station.longitude, station.latitude),
    ),
    circleRadius: highlighted ? 8.5 : 5.5,
    circleColor: _mapboxColor(
      highlighted ? const Color(0xFFFFD166) : const Color(0xFF55D6FF),
    ),
    circleOpacity: highlighted ? 1 : .92,
    circleStrokeColor: _mapboxColor(
      highlighted ? Colors.white : const Color(0xFF06141D),
    ),
    circleStrokeWidth: highlighted ? 3.2 : 2.0,
    circleSortKey: highlighted ? 60 : 20,
    customData: <String, Object>{
      'type': 'water_station',
      'stationId': station.id,
    },
  );

  Future<void> _syncUserAnnotation() async {
    final manager = _userAnnotationManager;
    final location = _currentLocation;
    if (!_isMapReady || manager == null || location == null) return;

    await manager.deleteAll();
    await manager.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        ),
        circleRadius: 8,
        circleColor: _mapboxColor(const Color(0xFF67D04B)),
        circleOpacity: .96,
        circleStrokeColor: _mapboxColor(Colors.white),
        circleStrokeWidth: 3,
        circleSortKey: 50,
        customData: const <String, Object>{'type': 'current_location'},
      ),
    );
  }

  void _handleStationAnnotationTap(mapbox.CircleAnnotation annotation) {
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

    _openStation(station);
  }

  Future<void> _openStation(Station station) async {
    _waterService.selectStation(station);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StationDetailsPage(station: station),
      ),
    );
  }

  Future<void> _openSearch() async {
    final selected = await showSearch<MapSearchResult?>(
      context: context,
      delegate: _MapSearchDelegate(
        searchService: _searchService,
        stations: _stations,
        hintText: context.l10n.mapSearchHint,
        noResultsText: context.l10n.noMapSearchResult,
      ),
    );

    if (selected == null || !mounted) return;
    if (!_stationLayerVisible) {
      setState(() {
        _temporarilyHighlightedStation = _stationForSearchResult(selected);
      });
      await _syncStationAnnotations();
    }
    _moveCamera(LatLng(selected.latitude, selected.longitude), zoom: 13.5);
  }

  Station? _stationForSearchResult(MapSearchResult result) {
    for (final station in _stations) {
      if (station.name == result.name &&
          (station.latitude - result.latitude).abs() < .000001 &&
          (station.longitude - result.longitude).abs() < .000001) {
        return station;
      }
    }
    return null;
  }

  Future<void> _toggleStationLayer() async {
    setState(() {
      _stationLayerVisible = !_stationLayerVisible;
      _temporarilyHighlightedStation = null;
    });
    await _syncStationAnnotations();
  }

  void _toggleActions() {
    setState(() => _actionsExpanded = !_actionsExpanded);
  }

  void _runAction(VoidCallback action) {
    setState(() => _actionsExpanded = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _currentLocation ?? _fallbackCamera;
    final languageCode = Localizations.localeOf(context).languageCode;
    final mapTitle = languageCode == 'ro' ? 'Harta Pescarilor' : 'Anglers Map';
    final fishingSpotLabel = languageCode == 'ro'
        ? 'Loc de pescuit'
        : 'Fishing Spot';
    final fishingSpotTooltip = languageCode == 'ro'
        ? 'Adaugă loc de pescuit'
        : 'Add fishing spot';
    final actionsLabel = languageCode == 'ro' ? 'Acțiuni' : 'Actions';
    final stationLayerLabel = languageCode == 'ro'
        ? (_stationLayerVisible ? 'Ascunde stațiile' : 'Arată stațiile')
        : (_stationLayerVisible ? 'Hide stations' : 'Show stations');

    return Scaffold(
      backgroundColor: const Color(0xFF071018),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final shortestSide = width < height ? width : height;
            final isLandscape = width > height;
            final isTablet = shortestSide >= 600;
            final singleLineHeader = isLandscape || width >= 360;
            final horizontalInset = (width * .035)
                .clamp(10.0, isTablet ? 32.0 : 20.0)
                .toDouble();
            final wordmarkHeight = (shortestSide * .06)
                .clamp(22.0, isTablet ? 36.0 : 30.0)
                .toDouble();
            final titleFontSize = (shortestSide * .035)
                .clamp(13.5, isTablet ? 21.0 : 17.0)
                .toDouble();
            final headerHeight = isLandscape
                ? (height * .14).clamp(50.0, isTablet ? 68.0 : 58.0).toDouble()
                : singleLineHeader
                ? (height * .10).clamp(56.0, isTablet ? 76.0 : 64.0).toDouble()
                : (height * .13).clamp(76.0, 92.0).toDouble();
            final controlGap = (height * .015).clamp(8.0, 14.0).toDouble();
            final controlsTop = headerHeight + controlGap;
            final controlSpacing = (height * .012).clamp(8.0, 12.0).toDouble();
            final controlSize = (shortestSide * .11)
                .clamp(40.0, isTablet ? 48.0 : 44.0)
                .toDouble();
            final actionsTop = controlsTop + 2 * (controlSize + controlSpacing);
            final railSpacing = (controlSpacing * .82)
                .clamp(6.0, 10.0)
                .toDouble();
            final availableLabelWidth =
                width - 2 * horizontalInset - controlSize - railSpacing;
            final labelMaxWidth = availableLabelWidth
                .clamp(92.0, isTablet ? 180.0 : 172.0)
                .toDouble();

            return Stack(
              fit: StackFit.expand,
              children: [
                MapboxMapView(
                  key: const ValueKey('aifishmap-map-page-mapbox'),
                  styleUri: _satelliteStreetsStyle,
                  initialCenter: initialCenter,
                  onMapCreated: _onMapCreated,
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: headerHeight,
                  child: _FullMapHeader(
                    title: mapTitle,
                    horizontalInset: horizontalInset,
                    wordmarkHeight: wordmarkHeight,
                    titleFontSize: titleFontSize,
                    singleLine: singleLineHeader,
                  ),
                ),
                Positioned(
                  left: horizontalInset,
                  top: controlsTop,
                  child: _MapToolButton(
                    tooltip: context.l10n.searchStation,
                    icon: Icons.search_rounded,
                    size: controlSize,
                    onTap: _openSearch,
                  ),
                ),
                Positioned(
                  right: horizontalInset,
                  top: controlsTop,
                  child: Column(
                    children: [
                      _MapToolButton(
                        tooltip: context.l10n.youAreHere,
                        icon: Icons.my_location_rounded,
                        size: controlSize,
                        accentColor: const Color(0xFF67D04B),
                        isLoading: _isLocating,
                        onTap: () => _locateUser(recenter: true),
                      ),
                      SizedBox(height: controlSpacing),
                      _MapToolButton(
                        tooltip: stationLayerLabel,
                        icon: Icons.water_drop_rounded,
                        size: controlSize,
                        accentColor: _stationLayerVisible
                            ? const Color(0xFF12D8D6)
                            : null,
                        foregroundColor: _stationLayerVisible
                            ? null
                            : Colors.white70,
                        isActive: _stationLayerVisible,
                        isLoading: _isLoadingStations,
                        onTap: _toggleStationLayer,
                      ),
                      SizedBox(height: controlSpacing),
                      _MapToolButton(
                        tooltip: actionsLabel,
                        icon: Icons.bolt_rounded,
                        size: controlSize,
                        accentColor: const Color(0xFFA970FF),
                        isActive: _actionsExpanded,
                        onTap: _toggleActions,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: isLandscape
                      ? horizontalInset + controlSize + railSpacing
                      : horizontalInset,
                  top: isLandscape
                      ? actionsTop
                      : actionsTop + controlSize + railSpacing,
                  child: _MapActionRail(
                    expanded: _actionsExpanded,
                    landscape: isLandscape,
                    buttonSize: controlSize,
                    spacing: railSpacing,
                    labelMaxWidth: labelMaxWidth,
                    actions: [
                      _MapRailAction(
                        icon: Icons.phishing_rounded,
                        label: context.l10n.addCatch,
                        color: const Color(0xFFB7F34A),
                        onTap: () => _runAction(widget.onAddCatch),
                      ),
                      _MapRailAction(
                        icon: Icons.add_location_alt_rounded,
                        label: fishingSpotLabel,
                        tooltip: fishingSpotTooltip,
                        color: const Color(0xFFFFA34D),
                        onTap: () => _runAction(
                          () =>
                              widget.onCreateReport(ReportCategory.goodFishing),
                        ),
                      ),
                      _MapRailAction(
                        icon: Icons.campaign_rounded,
                        label: context.l10n.report,
                        color: const Color(0xFFB78CFF),
                        onTap: () => _runAction(
                          () => widget.onCreateReport(
                            ReportCategory.fishActivity,
                          ),
                        ),
                      ),
                      _MapRailAction(
                        icon: Icons.favorite_rounded,
                        label: context.l10n.favorites,
                        color: const Color(0xFFFF75B5),
                        onTap: () => _runAction(widget.onOpenFavorites),
                      ),
                    ],
                  ),
                ),
                if (_stationLoadError != null)
                  Positioned(
                    left: horizontalInset,
                    right: horizontalInset,
                    bottom: controlGap,
                    child: _MapMessage(text: _stationLoadError!),
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

class _FullMapHeader extends StatelessWidget {
  const _FullMapHeader({
    required this.title,
    required this.horizontalInset,
    required this.wordmarkHeight,
    required this.titleFontSize,
    required this.singleLine,
  });

  final String title;
  final double horizontalInset;
  final double wordmarkHeight;
  final double titleFontSize;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final wordmark = Image.asset(
      'assets/branding/fluviai_wordmark.png',
      height: wordmarkHeight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
    final titleWidget = Text(
      '• $title',
      maxLines: singleLine ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: .94),
        fontSize: titleFontSize,
        height: 1.08,
        fontWeight: FontWeight.w600,
        letterSpacing: .1,
        shadows: const [
          Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
    );

    return IgnorePointer(
      child: Semantics(
        header: true,
        label: 'FluviAI • $title',
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF06101B).withValues(alpha: .92),
                  const Color(0xFF06101B).withValues(alpha: .58),
                  const Color(0xFF06101B).withValues(alpha: 0),
                ],
                stops: const [0, .56, 1],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                8,
                horizontalInset,
                singleLine ? 14 : 16,
              ),
              child: singleLine
                  ? Row(
                      children: [
                        wordmark,
                        const SizedBox(width: 9),
                        Flexible(child: titleWidget),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        wordmark,
                        const SizedBox(height: 5),
                        Flexible(child: titleWidget),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapRailAction {
  const _MapRailAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final Color color;
  final VoidCallback onTap;
}

class _MapActionRail extends StatelessWidget {
  const _MapActionRail({
    required this.expanded,
    required this.landscape,
    required this.buttonSize,
    required this.spacing,
    required this.labelMaxWidth,
    required this.actions,
  });

  final bool expanded;
  final bool landscape;
  final double buttonSize;
  final double spacing;
  final double labelMaxWidth;
  final List<_MapRailAction> actions;

  @override
  Widget build(BuildContext context) {
    final rail = landscape
        ? Row(
            key: const ValueKey('map-actions-landscape'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) SizedBox(width: spacing),
                _MapRailActionButton(
                  action: actions[index],
                  buttonSize: buttonSize,
                  labelMaxWidth: labelMaxWidth,
                  showLabel: false,
                ),
              ],
            ],
          )
        : Column(
            key: const ValueKey('map-actions-portrait'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) SizedBox(height: spacing),
                _MapRailActionButton(
                  action: actions[index],
                  buttonSize: buttonSize,
                  labelMaxWidth: labelMaxWidth,
                  showLabel: true,
                ),
              ],
            ],
          );

    return IgnorePointer(
      ignoring: !expanded,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        reverseDuration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.10, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: expanded
            ? rail
            : const SizedBox.shrink(key: ValueKey('map-actions-closed')),
      ),
    );
  }
}

class _MapRailActionButton extends StatelessWidget {
  const _MapRailActionButton({
    required this.action,
    required this.buttonSize,
    required this.labelMaxWidth,
    required this.showLabel,
  });

  final _MapRailAction action;
  final double buttonSize;
  final double labelMaxWidth;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          _MapActionLabel(
            label: action.label,
            maxWidth: labelMaxWidth,
            buttonSize: buttonSize,
            color: action.color,
          ),
          const SizedBox(width: 6),
        ],
        _MapToolButton(
          tooltip: action.tooltip ?? action.label,
          icon: action.icon,
          size: buttonSize,
          accentColor: action.color,
          onTap: action.onTap,
        ),
      ],
    );
  }
}

class _MapActionLabel extends StatelessWidget {
  const _MapActionLabel({
    required this.label,
    required this.maxWidth,
    required this.buttonSize,
    required this.color,
  });

  final String label;
  final double maxWidth;
  final double buttonSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final height = (buttonSize * .72).clamp(30.0, 36.0).toDouble();
    final compact = maxWidth < 110;
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: IntrinsicWidth(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                height: height,
                padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF101720).withValues(alpha: .48),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: .13)),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .05),
                      blurRadius: 10,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .92),
                      fontSize: compact ? 10.0 : 11.0,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
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

class MapboxMapView extends StatelessWidget {
  const MapboxMapView({
    super.key,
    required this.styleUri,
    required this.initialCenter,
    required this.onMapCreated,
  });

  final String styleUri;
  final LatLng initialCenter;
  final ValueChanged<mapbox.MapboxMap> onMapCreated;

  @override
  Widget build(BuildContext context) {
    return mapbox.MapWidget(
      key: key,
      textureView: true,
      styleUri: styleUri,
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            initialCenter.longitude,
            initialCenter.latitude,
          ),
        ),
        zoom: 12.5,
      ),
      onMapCreated: onMapCreated,
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
      return _buildResults(stations.map(_stationResult));
    }

    return FutureBuilder<List<MapSearchResult>>(
      future: _combinedResults(trimmed),
      builder: (context, snapshot) {
        final stationFallback = searchService.searchStations(trimmed, stations);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildResults(stationFallback);
        }

        final results = snapshot.data ?? stationFallback;
        if (results.isEmpty) return Center(child: Text(noResultsText));
        return _buildResults(results);
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
        return _buildResults(results);
      },
    );
  }

  Widget _buildResults(Iterable<MapSearchResult> results) {
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

class _MapToolButton extends StatelessWidget {
  const _MapToolButton({
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.onTap,
    this.isLoading = false,
    this.accentColor,
    this.foregroundColor,
    this.isActive = false,
  });

  final String tooltip;
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final bool isLoading;
  final Color? accentColor;
  final Color? foregroundColor;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final borderRadius = (size * .34).clamp(13.0, 16.0).toDouble();
    final iconSize = (size * .48).clamp(19.0, 23.0).toDouble();
    final loaderSize = (size * .4).clamp(16.0, 20.0).toDouble();
    final effectiveForegroundColor =
        foregroundColor ?? accentColor ?? Colors.white;

    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: accentColor == null
                    ? const Color(0xFF101720).withValues(alpha: .72)
                    : Color.alphaBlend(
                        accentColor!.withValues(alpha: isActive ? .16 : .07),
                        const Color(0xFF101720).withValues(alpha: .68),
                      ),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color:
                      accentColor?.withValues(alpha: isActive ? .42 : .24) ??
                      Colors.white.withValues(alpha: .15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                  if (accentColor != null)
                    BoxShadow(
                      color: accentColor!.withValues(
                        alpha: isActive ? .18 : .10,
                      ),
                      blurRadius: 12,
                      spreadRadius: -4,
                    ),
                ],
              ),
              child: Center(
                child: isLoading
                    ? SizedBox.square(
                        dimension: loaderSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: effectiveForegroundColor,
                        ),
                      )
                    : Icon(
                        icon,
                        color: effectiveForegroundColor,
                        size: iconSize,
                      ),
              ),
            ),
          ),
        ),
      ),
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
