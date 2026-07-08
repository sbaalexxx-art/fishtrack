import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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

  @override
  State<HomeMapRenderer> createState() => _HomeMapRendererState();
}

class _HomeMapRendererState extends State<HomeMapRenderer>
    with AutomaticKeepAliveClientMixin<HomeMapRenderer> {
  static const _satelliteStreetsStyle =
      'mapbox://styles/mapbox/satellite-streets-v12';

  late final Widget _mapWidget;

  /// Build gesture recognizers to prevent parent ScrollView from intercepting map gestures.
  /// EagerGestureRecognizer claims gestures immediately so they don't bubble up.
  Set<Factory<OneSequenceGestureRecognizer>> _buildGestureRecognizers() {
    return {
      Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
    };
  }

  @override
  void initState() {
    super.initState();
    _mapWidget = mapbox.MapWidget(
      key: const ValueKey('aifishmap-home-mapbox'),
      // TextureView is more stable for the small Home map because it is
      // embedded inside a rounded, scrollable premium card. SurfaceView can
      // briefly detach/recreate and cause black frames or camera resets.
      textureView: true,
      styleUri: _satelliteStreetsStyle,
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(21.3895, 44.8148)),
        zoom: 12.5,
      ),
      gestureRecognizers: _buildGestureRecognizers(),
      onMapCreated: (_) {
        widget.onMapReady?.call();
      },
    );
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
