import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MapboxTestPage extends StatefulWidget {
  const MapboxTestPage({super.key});

  @override
  State<MapboxTestPage> createState() => _MapboxTestPageState();
}

class _MapboxTestPageState extends State<MapboxTestPage> {
  MapboxMap? _mapboxMap;

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: MapWidget(
            key: const ValueKey('aifishmap-mapbox-test'),
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(28.0, 45.3)),
              zoom: 6.8,
            ),
            styleUri: MapboxStyles.OUTDOORS,
            textureView: true,
            onMapCreated: _onMapCreated,
          ),
        ),
      ),
    );
  }
}
