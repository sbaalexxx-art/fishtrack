import 'package:flutter/foundation.dart';

import '../../models/station.dart';
import '../../services/build_mode_service.dart';
import '../../services/diagnostics_service.dart';

/// Debug-only runtime provenance for the physical Map gate.
///
/// Values are limited to entity identity, coordinates and aggregate counts.
/// No credentials, request headers or backend payloads are logged.
void logMapRuntime(
  String event, {
  Station? station,
  Map<String, Object?> fields = const {},
}) {
  if (!BuildModeService.isDeveloperVisible) return;
  final values = <String, Object?>{
    if (station != null) ...{
      'stationId': station.id,
      'stationName': station.name,
      'latitude': station.latitude,
      'longitude': station.longitude,
      'source': station.waterLevelSource,
    },
    ...fields,
  };
  DiagnosticsService.instance.record(
    category: DiagnosticCategory.navigation,
    operation: 'map_runtime',
    message: event,
    metadata: values,
  );
  if (kDebugMode) {
    final detail = values.entries
        .map((entry) => '${entry.key}=${entry.value ?? 'absent'}')
        .join(' ');
    debugPrint(
      '[FluviAI.MapRuntime] $event${detail.isEmpty ? '' : ' $detail'}',
    );
  }
}
