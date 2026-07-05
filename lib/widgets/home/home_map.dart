import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/community_service.dart';

enum MapBaseLayer { standard, satellite, fishingMode }

enum MapOverlay { community, catches, favorites }

class HomeMap extends StatelessWidget {
  final List<CommunityPost> reports;
  final ValueChanged<CommunityPost>? onReportTap;
  final MapController? mapController;
  final LatLng? currentLocation;
  final VoidCallback? onMapReady;
  final MapBaseLayer baseLayer;
  final Set<MapOverlay> overlays;

  const HomeMap({
    super.key,
    required this.reports,
    this.onReportTap,
    this.mapController,
    this.currentLocation,
    this.onMapReady,
    this.baseLayer = MapBaseLayer.standard,
    this.overlays = const {MapOverlay.community},
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: const LatLng(45.3, 28.0),
          initialZoom: 6.8,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
          onMapReady: onMapReady,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.aifishmap.app',
            panBuffer: 0,
          ),
          MarkerLayer(
            markers: [
              if (overlays.contains(MapOverlay.community))
                ..._clusters(reports).map((cluster) {
                  final report = cluster.reports.first;
                  return Marker(
                    point: cluster.center,
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: cluster.reports.length == 1
                          ? () => onReportTap?.call(report)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 5,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: cluster.reports.length == 1
                            ? const Icon(
                                Icons.campaign_rounded,
                                color: Colors.white,
                                size: 15,
                              )
                            : Center(
                                child: Text(
                                  '${cluster.reports.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  );
                }),
              if (currentLocation case final location?)
                Marker(
                  point: location,
                  width: 30,
                  height: 30,
                  child: Tooltip(
                    message: 'You are here',
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF147BFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF147BFF,
                            ).withValues(alpha: .45),
                            blurRadius: 12,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_pin_circle_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static List<_ReportCluster> _clusters(List<CommunityPost> reports) {
    const cellSize = .06;
    final cells = <String, List<CommunityPost>>{};
    for (final report in reports) {
      if (!report.isActiveReport ||
          report.latitude == null ||
          report.longitude == null) {
        continue;
      }
      final key =
          '${(report.latitude! / cellSize).floor()}:'
          '${(report.longitude! / cellSize).floor()}';
      cells.putIfAbsent(key, () => []).add(report);
    }
    return cells.values
        .map((items) {
          final latitude =
              items.fold<double>(0, (sum, item) => sum + item.latitude!) /
              items.length;
          final longitude =
              items.fold<double>(0, (sum, item) => sum + item.longitude!) /
              items.length;
          return _ReportCluster(LatLng(latitude, longitude), items);
        })
        .toList(growable: false);
  }
}

class _ReportCluster {
  const _ReportCluster(this.center, this.reports);
  final LatLng center;
  final List<CommunityPost> reports;
}
