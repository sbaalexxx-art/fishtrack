import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  final List<CommunityPost> reports;
  final List<Station> stations;
  final ValueChanged<CommunityPost>? onReportTap;
  final ValueChanged<Station>? onStationTap;
  final MapController? mapController;
  final LatLng? currentLocation;
  final VoidCallback? onMapReady;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;
  final Set<String> favoriteStationIds;
  final List<CommunityPost> recentCatches;

  const HomeMap({
    super.key,
    required this.reports,
    this.stations = const [],
    this.onReportTap,
    this.onStationTap,
    this.mapController,
    this.currentLocation,
    this.onMapReady,
    this.baseLayer = MapBaseLayer.standard,
    this.overlays = const {
      MapOverlay.waterStations,
      MapOverlay.communityReports,
    },
    this.favoriteStationIds = const {},
    this.recentCatches = const [],
  });

  @override
  Widget build(BuildContext context) {
    return HomeMapRenderer(
      reports: reports,
      stations: stations,
      onReportTap: onReportTap,
      onStationTap: onStationTap,
      mapController: mapController,
      currentLocation: currentLocation,
      onMapReady: onMapReady,
      baseLayer: baseLayer,
      overlays: overlays,
      favoriteStationIds: favoriteStationIds,
      recentCatches: recentCatches,
    );
  }
}
