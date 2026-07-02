import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';

class HomeMap extends StatelessWidget {
  final List<Station> stations;
  final ValueChanged<Station>? onStationTap;

  const HomeMap({super.key, required this.stations, this.onStationTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(45.3, 28.0),
          initialZoom: 6.8,
          interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.aifishmap.app',
          ),
          MarkerLayer(
            markers: stations.map((station) {
              return Marker(
                point: LatLng(station.latitude, station.longitude),
                width: 46,
                height: 46,
                child: GestureDetector(
                  onTap: () => onStationTap?.call(station),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
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
                      Icons.phishing,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
