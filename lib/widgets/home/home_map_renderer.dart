import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../models/station.dart';
import '../../services/community_service.dart';
import 'home_map.dart';

class HomeMapRenderer extends StatefulWidget {
  const HomeMapRenderer({
    super.key,
    required this.reports,
    this.stations = const [],
    this.onReportTap,
    this.onStationTap,
    this.currentLocation,
    this.onMapReady,
    this.onMapboxMapCreated,
    this.baseLayer = MapBaseLayer.standard,
    this.overlays = const {
      MapOverlay.waterStations,
      MapOverlay.communityReports,
    },
    this.favoriteStationIds = const {},
    this.recentCatches = const [],
  });

  final List<CommunityPost> reports;
  final List<Station> stations;
  final ValueChanged<CommunityPost>? onReportTap;
  final ValueChanged<Station>? onStationTap;
  final LatLng? currentLocation;
  final VoidCallback? onMapReady;
  final ValueChanged<mapbox.MapboxMap>? onMapboxMapCreated;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;
  final Set<String> favoriteStationIds;
  final List<CommunityPost> recentCatches;

  @override
  State<HomeMapRenderer> createState() => _HomeMapRendererState();
}

class _HomeMapRendererState extends State<HomeMapRenderer>
    with AutomaticKeepAliveClientMixin<HomeMapRenderer> {
  static const _satelliteStreetsStyle =
      'mapbox://styles/mapbox/satellite-streets-v12';
  static const _fallbackCamera = LatLng(44.8148, 21.3895);

  mapbox.MapboxMap? _mapboxMap;
  late final Widget _mapWidget;
  bool _didApplyLocationCamera = false;

  Set<Factory<OneSequenceGestureRecognizer>> _buildGestureRecognizers() {
    return {
      Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
    };
  }

  @override
  void initState() {
    super.initState();
    final initialCenter = widget.currentLocation ?? _fallbackCamera;
    _didApplyLocationCamera = widget.currentLocation != null;
    _mapWidget = mapbox.MapWidget(
      key: const ValueKey('aifishmap-home-mapbox'),
      textureView: true,
      styleUri: _satelliteStreetsStyle,
      cameraOptions: _cameraFor(initialCenter, zoom: 12.5),
      gestureRecognizers: _buildGestureRecognizers(),
      onMapCreated: _handleMapCreated,
    );
  }

  @override
  void didUpdateWidget(covariant HomeMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final location = widget.currentLocation;
    if (location == null || _didApplyLocationCamera) return;
    _didApplyLocationCamera = true;
    _setCamera(location, zoom: 12.5);
  }

  void _handleMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    widget.onMapboxMapCreated?.call(mapboxMap);
    widget.onMapReady?.call();

    final location = widget.currentLocation;
    if (location != null && !_didApplyLocationCamera) {
      _didApplyLocationCamera = true;
      _setCamera(location, zoom: 12.5);
    }
  }

  mapbox.CameraOptions _cameraFor(LatLng target, {required double zoom}) {
    return mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(target.longitude, target.latitude),
      ),
      zoom: zoom,
    );
  }

  void _setCamera(LatLng target, {required double zoom}) {
    _mapboxMap?.setCamera(_cameraFor(target, zoom: zoom));
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(18),
      ),
      child: _mapWidget,
    );
  }
}
