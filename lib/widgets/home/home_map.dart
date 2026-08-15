import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../services/community_service.dart';
import 'home_map_renderer.dart';

enum MapBaseLayer { standard, satellite, fishingMode }

enum MapOverlay { communityReports, recentCatches }

class HomeMap extends StatelessWidget {
  const HomeMap({
    super.key,
    required this.reports,
    required this.initialCamera,
    this.onMapTap,
    this.onReportTap,
    this.currentLocation,
    this.explorationCenter,
    this.onMapReady,
    this.onMapboxMapCreated,
    this.baseLayer = MapBaseLayer.satellite,
    this.overlays = const {MapOverlay.communityReports},
    this.recentCatches = const [],
  });

  final List<CommunityPost> reports;
  final LatLng initialCamera;
  final VoidCallback? onMapTap;
  final ValueChanged<CommunityPost>? onReportTap;
  final LatLng? currentLocation;
  final LatLng? explorationCenter;
  final VoidCallback? onMapReady;
  final ValueChanged<mapbox.MapboxMap>? onMapboxMapCreated;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;
  final List<CommunityPost> recentCatches;

  @override
  Widget build(BuildContext context) {
    return HomeMapRenderer(
      reports: reports,
      initialCamera: initialCamera,
      onMapTap: onMapTap,
      onReportTap: onReportTap,
      currentLocation: currentLocation,
      explorationCenter: explorationCenter,
      onMapReady: onMapReady,
      onMapboxMapCreated: onMapboxMapCreated,
      baseLayer: baseLayer,
      overlays: overlays,
      recentCatches: recentCatches,
    );
  }
}
