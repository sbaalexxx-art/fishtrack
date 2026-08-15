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

class WaterForecastPoint {
  const WaterForecastPoint({
    required this.hours,
    required this.waterLevelCm,
  });

  final int hours;
  final double waterLevelCm;

  static WaterForecastPoint? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final hoursValue = map['hours'];
    final levelValue = map['water_level_cm'];
    final hours = hoursValue is num
        ? hoursValue.toInt()
        : int.tryParse(hoursValue?.toString() ?? '');
    final waterLevelCm = levelValue is num
        ? levelValue.toDouble()
        : double.tryParse(levelValue?.toString() ?? '');
    if (hours == null ||
        hours <= 0 ||
        waterLevelCm == null ||
        !waterLevelCm.isFinite) {
      return null;
    }
    return WaterForecastPoint(hours: hours, waterLevelCm: waterLevelCm);
  }

  static List<WaterForecastPoint> listFromJson(Object? raw) {
    if (raw is! Iterable) return const <WaterForecastPoint>[];
    return List<WaterForecastPoint>.unmodifiable(
      raw.map(tryFromJson).whereType<WaterForecastPoint>(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hours': hours,
    'water_level_cm': waterLevelCm,
  };
}

enum WaterMeasurementPrecision {
  exact,
  date,
  interval,
  relative,
  unknown;

  static WaterMeasurementPrecision parse(Object? value) =>
      switch (value?.toString().trim().toLowerCase()) {
        'exact' => WaterMeasurementPrecision.exact,
        'date' || 'date_only' => WaterMeasurementPrecision.date,
        'interval' => WaterMeasurementPrecision.interval,
        'relative' => WaterMeasurementPrecision.relative,
        _ => WaterMeasurementPrecision.unknown,
      };
}

class WaterLevel {
  const WaterLevel({
    required this.stationId,
    required this.value,
    required this.timestamp,
    required this.trend,
    this.freshnessTimestamp,
    this.measurementPrecision = WaterMeasurementPrecision.exact,
    this.source = WaterLevelSource.manualFallback,
    this.unit = 'cm',
    this.sourceName = 'Supabase water_levels',
    this.hasKnownTrend = false,
    this.metricCode = 'water_level',
    this.measurementDatum = 'source_native',
    this.historyContract = 'canonical_water_level',
    this.isQualityValid = true,
    this.measurementResolution,
    this.reportedDeltaCm24h,
    this.waterTemperatureC,
    this.forecast = const <WaterForecastPoint>[],
    this.forecastUpdatedAt,
  });

  final String stationId;
  final double value;
  final DateTime timestamp;
  final DateTime? freshnessTimestamp;
  final WaterMeasurementPrecision measurementPrecision;
  final WaterTrend trend;
  final WaterLevelSource source;
  final String unit;
  final String sourceName;
  final bool hasKnownTrend;
  final String metricCode;
  final String measurementDatum;
  final String historyContract;
  final bool isQualityValid;
  final double? measurementResolution;

  /// Provider-published 24h variation. When present, this is authoritative
  /// for the fisherman-facing daily delta and must not be reconstructed from
  /// sparse history.
  final double? reportedDeltaCm24h;

  /// Provider-published water temperature for the same observation.
  final double? waterTemperatureC;

  /// Provider-published water-level forecast points. These remain optional and
  /// are never synthesized by the client.
  final List<WaterForecastPoint> forecast;
  final DateTime? forecastUpdatedAt;

  DateTime get effectiveFreshnessTimestamp => freshnessTimestamp ?? timestamp;

  /// A trend is presentation-safe only when it is backed by compatible
  /// observations. [trend] remains non-nullable for legacy source adapters,
  /// but must never be used as an unknown-state fallback.
  WaterTrend? get knownTrend => hasKnownTrend ? trend : null;

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
    final freshnessTimestamp = DateTime.tryParse(
      json['freshness_timestamp']?.toString() ?? '',
    );
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
      freshnessTimestamp: freshnessTimestamp,
      measurementPrecision: WaterMeasurementPrecision.parse(
        json['observed_at_precision'],
      ),
      trend: parsedTrend ?? WaterTrend.stable,
      hasKnownTrend: parsedTrend != null,
      source: source,
      unit: json['unit']?.toString().trim().isNotEmpty == true
          ? json['unit'].toString().trim()
          : 'cm',
      metricCode: json['metric_code']?.toString().trim().isNotEmpty == true
          ? json['metric_code'].toString().trim()
          : 'water_level',
      measurementDatum:
          json['measurement_datum']?.toString().trim().isNotEmpty == true
          ? json['measurement_datum'].toString().trim()
          : 'source_native',
      historyContract:
          json['history_contract']?.toString().trim().isNotEmpty == true
          ? json['history_contract'].toString().trim()
          : 'canonical_water_level',
      isQualityValid: json['is_quality_valid'] != false,
      measurementResolution: json['measurement_resolution'] is num
          ? (json['measurement_resolution'] as num).toDouble()
          : double.tryParse(json['measurement_resolution']?.toString() ?? ''),
      reportedDeltaCm24h: json['reported_delta_cm_24h'] is num
          ? (json['reported_delta_cm_24h'] as num).toDouble()
          : double.tryParse(json['reported_delta_cm_24h']?.toString() ?? ''),
      waterTemperatureC: json['water_temperature_c'] is num
          ? (json['water_temperature_c'] as num).toDouble()
          : double.tryParse(json['water_temperature_c']?.toString() ?? ''),
      forecast: WaterForecastPoint.listFromJson(json['forecast']),
      forecastUpdatedAt: DateTime.tryParse(
        json['forecast_updated_at']?.toString() ?? '',
      ),
    );
  }
}
