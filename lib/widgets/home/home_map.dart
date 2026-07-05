import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/community_service.dart';

class HomeMap extends StatelessWidget {
  final List<CommunityPost> reports;
  final ValueChanged<CommunityPost>? onReportTap;
  final MapController? mapController;
  final LatLng? currentLocation;
  final VoidCallback? onMapReady;

  const HomeMap({
    super.key,
    required this.reports,
    this.onReportTap,
    this.mapController,
    this.currentLocation,
    this.onMapReady,
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
          ),
          MarkerLayer(
            markers: [
              ...reports
                  .where(
                    (report) =>
                        report.isActiveReport &&
                        report.latitude != null &&
                        report.longitude != null,
                  )
                  .map((report) {
                    return Marker(
                      point: LatLng(report.latitude!, report.longitude!),
                      width: 46,
                      height: 46,
                      child: GestureDetector(
                        onTap: () => onReportTap?.call(report),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE65100),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    );
                  }),
              if (currentLocation case final location?)
                Marker(
                  point: location,
                  width: 38,
                  height: 38,
                  child: Tooltip(
                    message: 'You are here',
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF147BFF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
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
                        size: 22,
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
}
