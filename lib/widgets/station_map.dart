import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/station.dart';

class StationMap extends StatelessWidget {
  final Station station;

  const StationMap({super.key, required this.station});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(station.latitude, station.longitude),
            initialZoom: 11,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.fishtrack.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(station.latitude, station.longitude),
                  width: 60,
                  height: 60,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 42,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
