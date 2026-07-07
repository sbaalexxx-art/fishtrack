import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../l10n/l10n.dart';

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  static const _satelliteStreetsStyle =
      'mapbox://styles/mapbox/satellite-streets-v12';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.fishingMap), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: MapWidget(
              key: const ValueKey('aifishmap-map-page-mapbox'),
              textureView: true,
              styleUri: _satelliteStreetsStyle,
              cameraOptions: CameraOptions(
                center: Point(coordinates: Position(21.3895, 44.8148)),
                zoom: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
