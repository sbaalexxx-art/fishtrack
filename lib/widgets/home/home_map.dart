import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/station.dart';

class HomeMap extends StatelessWidget {
  final List<Station> stations;

  const HomeMap({super.key, required this.stations});

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(45.3, 28.0),
        initialZoom: 6.8,
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
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 36),
            );
          }).toList(),
        ),
      ],
    );
  }
}
