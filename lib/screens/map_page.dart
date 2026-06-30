import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Harta Apelor"), centerTitle: true),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(45.5, 27.2),
          initialZoom: 6.8,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.fishtrack.app',
          ),

          MarkerLayer(
            markers: [
              Marker(
                point: const LatLng(43.9037, 25.9699),
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 38,
                ),
              ),

              Marker(
                point: const LatLng(44.3388, 28.0328),
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 38,
                ),
              ),

              Marker(
                point: const LatLng(45.1716, 28.7914),
                width: 50,
                height: 50,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
