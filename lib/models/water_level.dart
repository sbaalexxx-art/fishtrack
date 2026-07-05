import 'station.dart';

/// Official providers supported by the water-level module.
enum WaterLevelSource { afdj, danubeHis, danubeFis, supabase, unknown }

class WaterLevel {
  const WaterLevel({
    required this.stationId,
    required this.value,
    required this.timestamp,
    required this.trend,
    this.source = WaterLevelSource.unknown,
  });

  final String stationId;
  final double value;
  final DateTime timestamp;
  final WaterTrend trend;
  final WaterLevelSource source;

  static WaterLevel? tryFromJson(
    Map<String, dynamic> json, {
    String? fallbackStationId,
    WaterLevelSource source = WaterLevelSource.unknown,
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
