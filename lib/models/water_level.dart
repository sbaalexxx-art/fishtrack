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
    this.unit = 'cm',
    this.sourceName = 'Supabase water_levels',
    this.hasKnownTrend = false,
  });

  final String stationId;
  final double value;
  final DateTime timestamp;
  final WaterTrend trend;
  final WaterLevelSource source;
  final String unit;
  final String sourceName;
  final bool hasKnownTrend;

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
    if (stationId == null ||
        stationId.trim().isEmpty ||
        value == null ||
        !value.isFinite ||
        timestamp == null) {
      return null;
    }

    final parsedTrend = switch (json['trend']
        ?.toString()
        .trim()
        .toLowerCase()) {
      'rising' || 'creste' => WaterTrend.rising,
      'falling' || 'scade' => WaterTrend.falling,
      'stable' || 'stabil' => WaterTrend.stable,
      _ => null,
    };

    return WaterLevel(
      stationId: stationId,
      value: value,
      timestamp: timestamp,
      trend: parsedTrend ?? WaterTrend.stable,
      hasKnownTrend: parsedTrend != null,
      source: source,
    );
  }
}
