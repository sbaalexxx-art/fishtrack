import '../../models/station.dart';
import '../map/pending_map_camera.dart';

class ContextualMapEntry {
  const ContextualMapEntry({
    required this.source,
    this.station,
    this.cameraTarget,
  });

  factory ContextualMapEntry.browse({required String source}) =>
      ContextualMapEntry(source: source);

  factory ContextualMapEntry.forStation({
    required String source,
    required Station station,
  }) => ContextualMapEntry(source: source, station: station);

  factory ContextualMapEntry.forTarget({
    required String source,
    required RuntimeMapCameraTarget target,
  }) => ContextualMapEntry(source: source, cameraTarget: target);

  final String source;
  final Station? station;
  final RuntimeMapCameraTarget? cameraTarget;
}
