import 'station.dart';

/// Official providers supported by the water-level module.
enum WaterLevelSource {
  afdj,
  danubeHis,
  danubeFis,
  inhga,
  manualFallback;

  static WaterLevelSource parse(
    Object? value, {
    WaterLevelSource fallback = WaterLevelSource.manualFallback,
  }) => switch (value?.toString().trim().toLowerCase()) {
    'afdj' => WaterLevelSource.afdj,
    'danubehis' || 'danube_his' => WaterLevelSource.danubeHis,
    'danubefis' || 'danube_fis' => WaterLevelSource.danubeFis,
    'inhga' => WaterLevelSource.inhga,
    'manualfallback' || 'manual_fallback' => WaterLevelSource.manualFallback,
    _ => fallback,
  };
}

class WaterLevel {
  const WaterLevel({
    required this.stationId,
    required this.value,
    required this.timestamp,
    required this.trend,
    this.source = WaterLevelSource.manualFallback,
  });

  final String stationId;
  final double value;
  final DateTime timestamp;
  final WaterTrend trend;
  final WaterLevelSource source;

  static WaterLevel? tryFromJson(
    Map<String, dynamic> json, {
    String? fallbackStationId,
    WaterLevelSource source = WaterLevelSource.manualFallback,
  }) {
    final stationId = json['station_id']?.toString() ?? fallbackStationId;
    final value = json['value'] is num
        ? (json['value'] as num).toDouble()
        : double.tryParse(json['value']?.toString() ?? '');
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    if (stationId == null || value == null || timestamp == null) return null;

    return WaterLevel(
      stationId: stationId,
      value: value,
      timestamp: timestamp,
      trend: switch (json['trend']?.toString().trim().toLowerCase()) {
        'rising' || 'creste' => WaterTrend.rising,
        'falling' || 'scade' => WaterTrend.falling,
        _ => WaterTrend.stable,
      },
      source: source,
    );
  }
}
