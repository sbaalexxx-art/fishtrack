import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

abstract final class MapThemeStyle {
  static const String satellite =
      'mapbox://styles/mapbox/satellite-streets-v12';
  static const String standard = mapbox.MapboxStyles.STANDARD;
  static const String outdoors = mapbox.MapboxStyles.OUTDOORS;
  static const String streets = mapbox.MapboxStyles.MAPBOX_STREETS;
}
