import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../l10n/l10n.dart';
import '../models/station.dart';
import '../services/location_service.dart';
import '../services/map_search_service.dart';
import '../services/water_service.dart';
import 'station_details_page.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

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
  mapbox.CircleAnnotationManager? _userAnnotationManager;
  dynamic _stationTapEvents;

  List<Station> _stations = const [];
  LatLng? _currentLocation;
  LatLng? _pendingCameraTarget;
  double _pendingCameraZoom = 13.5;
  bool _isMapReady = false;
  bool _isLocating = false;
  bool _isLoadingStations = false;
  String? _stationLoadError;

  @override
  void initState() {
    super.initState();
    _loadStations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
  }

  @override
  void dispose() {
    _stationTapEvents?.cancel();
    _stationAnnotationManager?.deleteAll();
    _userAnnotationManager?.deleteAll();
    super.dispose();
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _isMapReady = true;

    _stationAnnotationManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    _stationTapEvents = _stationAnnotationManager?.tapEvents(
      onTap: _handleStationAnnotationTap,
    );
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
    if (!_isMapReady || manager == null) return;

    await manager.deleteAll();
    if (_stations.isEmpty) return;

    final annotations = _stations
        .map(
          (station) => mapbox.CircleAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(station.longitude, station.latitude),
            ),
            circleRadius: 5.5,
            circleColor: _mapboxColor(const Color(0xFF55D6FF)),
            circleOpacity: .92,
            circleStrokeColor: _mapboxColor(const Color(0xFF06141D)),
            circleStrokeWidth: 2.0,
            circleSortKey: 20,
            customData: <String, Object>{
              'type': 'water_station',
              'stationId': station.id,
            },
          ),
        )
        .toList(growable: false);

    await manager.createMulti(annotations);
  }

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
    _moveCamera(LatLng(selected.latitude, selected.longitude), zoom: 13.5);
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _currentLocation ?? _fallbackCamera;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.fishingMap),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MapboxMapView(
                  key: const ValueKey('aifishmap-map-page-mapbox'),
                  styleUri: _satelliteStreetsStyle,
                  initialCenter: initialCenter,
                  onMapCreated: _onMapCreated,
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _MapToolButton(
                    tooltip: context.l10n.searchStation,
                    icon: Icons.search_rounded,
                    onTap: _openSearch,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Column(
                    children: [
                      _MapToolButton(
                        tooltip: context.l10n.youAreHere,
                        icon: Icons.my_location_rounded,
                        isLoading: _isLocating,
                        onTap: () => _locateUser(recenter: true),
                      ),
                      const SizedBox(height: 8),
                      _MapToolButton(
                        tooltip: context.l10n.waterStations,
                        icon: Icons.water_drop_rounded,
                        isLoading: _isLoadingStations,
                        onTap: _loadStations,
                      ),
                    ],
                  ),
                ),
                if (_stationLoadError != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _MapMessage(text: _stationLoadError!),
                  ),
              ],
            ),
          ),
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
    required this.onTap,
    this.isLoading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF101720).withValues(alpha: .72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 22),
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
