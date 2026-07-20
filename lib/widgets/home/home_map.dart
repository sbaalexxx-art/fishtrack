import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../models/station.dart';
import '../../services/community_service.dart';
import 'home_map_renderer.dart';

enum MapBaseLayer { standard, satellite, fishingMode }

enum MapOverlay {
  waterStations,
  communityReports,
  recentCatches,
  favoriteStations,
}

class HomeMap extends StatelessWidget {
  const HomeMap({
    super.key,
    required this.reports,
    this.stations = const [],
    this.onReportTap,
    this.onStationTap,
    this.currentLocation,
    this.explorationCenter,
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
  final LatLng? explorationCenter;
  final VoidCallback? onMapReady;
  final ValueChanged<mapbox.MapboxMap>? onMapboxMapCreated;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;
  final Set<String> favoriteStationIds;
  final List<CommunityPost> recentCatches;

  @override
  Widget build(BuildContext context) {
    return HomeMapRenderer(
      reports: reports,
      stations: stations,
      onReportTap: onReportTap,
      onStationTap: onStationTap,
      currentLocation: currentLocation,
      explorationCenter: explorationCenter,
      onMapReady: onMapReady,
      onMapboxMapCreated: onMapboxMapCreated,
      baseLayer: baseLayer,
      overlays: overlays,
      favoriteStationIds: favoriteStationIds,
      recentCatches: recentCatches,
    );
  }
}
