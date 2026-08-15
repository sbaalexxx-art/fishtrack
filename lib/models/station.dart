enum WaterTrend { rising, falling, stable }

enum WaterBodyType { river, lake }

enum FishingDifficulty { easy, moderate, hard }

class Station {
  final String id;
  final String name;
  final String river;
  final double level;
  final WaterTrend trend;
  final double latitude;
  final double longitude;
  final DateTime lastUpdate;
  final DateTime? waterFreshnessTimestamp;
  final WaterBodyType waterBodyType;
  final List<String> species;
  final FishingDifficulty difficulty;
  final bool isFavorite;
  final bool hasWaterLevel;
  final String waterLevelUnit;
  final String waterLevelSource;
  final String waterMeasurementPrecision;
  final bool hasKnownTrend;
  final double? reportedDeltaCm24h;
  final double? waterTemperatureC;

  /// Raw dynamic values supplied by the station metadata row. They remain
  /// nullable because metadata identity can exist before an observed reading.
  final double? persistedLevel;
  final WaterTrend? persistedTrend;
  final DateTime? persistedLastUpdate;

  const Station({
    required this.id,
    required this.name,
    required this.river,
    required this.level,
    required this.trend,
    required this.latitude,
    required this.longitude,
    required this.lastUpdate,
    this.waterFreshnessTimestamp,
    this.waterBodyType = WaterBodyType.river,
    this.species = const [],
    this.difficulty = FishingDifficulty.moderate,
    this.isFavorite = false,
    this.hasWaterLevel = false,
    this.waterLevelUnit = 'cm',
    this.waterLevelSource = 'Supabase water_levels',
    this.waterMeasurementPrecision = 'exact',
    this.hasKnownTrend = false,
    this.reportedDeltaCm24h,
    this.waterTemperatureC,
    this.persistedLevel,
    this.persistedTrend,
    this.persistedLastUpdate,
  });

  static Station? tryFromJson(Map<String, dynamic> json) {
    final id = _stringValue(json['id']);
    final name = _stringValue(json['name']);
    final river = _stringValue(json['river']) ?? '';
    final latitude = _doubleValue(json['latitude']);
    final longitude = _doubleValue(json['longitude']);

    if (id == null ||
        name == null ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    final level = _doubleValue(json['level']);
    final trend = switch (_stringValue(json['trend'])?.toLowerCase()) {
      'rising' => WaterTrend.rising,
      'falling' => WaterTrend.falling,
      'stable' => WaterTrend.stable,
      _ => null,
    };
    final lastUpdate = _dateValue(json['last_update']);
    final waterFreshnessTimestamp = _dateValue(
      json['water_freshness_timestamp'],
    );
    final hasWaterLevel =
        _boolValue(json['has_water_level']) &&
        level != null &&
        lastUpdate != null;
    final hasKnownTrend = _boolValue(json['has_known_trend']) && trend != null;

    return Station(
      id: id,
      name: name,
      river: river,
      // Existing consumers are non-nullable and always gate dynamic fields on
      // hasWaterLevel/hasKnownTrend. NaN is deliberately ineligible as a real
      // reading, unlike a fabricated 0 cm value.
      level: level ?? double.nan,
      trend: trend ?? WaterTrend.stable,
      latitude: latitude,
      longitude: longitude,
      lastUpdate:
          lastUpdate ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      waterFreshnessTimestamp: waterFreshnessTimestamp,
      waterBodyType: _waterBodyType(json['water_type'] ?? json['type']),
      species: _species(json['species']),
      difficulty: _difficulty(json['difficulty']),
      isFavorite: _boolValue(json['is_favorite'] ?? json['favorite']),
      hasWaterLevel: hasWaterLevel,
      hasKnownTrend: hasKnownTrend,
      waterLevelUnit: _stringValue(json['water_level_unit']) ?? 'cm',
      waterLevelSource:
          _stringValue(json['water_level_source']) ?? 'Supabase water_levels',
      waterMeasurementPrecision:
          _stringValue(json['water_measurement_precision']) ?? 'exact',
      reportedDeltaCm24h: _doubleValue(json['reported_delta_cm_24h']),
      waterTemperatureC: _doubleValue(json['water_temperature_c']),
      persistedLevel: level,
      persistedTrend: trend,
      persistedLastUpdate: lastUpdate,
    );
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _doubleValue(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number?.isFinite == true ? number : null;
  }

  static DateTime? _dateValue(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  static WaterBodyType _waterBodyType(Object? value) =>
      value?.toString().toLowerCase() == 'lake'
      ? WaterBodyType.lake
      : WaterBodyType.river;

  static List<String> _species(Object? value) {
    final values = value is Iterable
        ? value
        : value?.toString().split(',') ?? const <String>[];
    return List<String>.unmodifiable(
      values
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty),
    );
  }

  static FishingDifficulty _difficulty(Object? value) =>
      switch (value?.toString().toLowerCase()) {
        'easy' => FishingDifficulty.easy,
        'hard' => FishingDifficulty.hard,
        _ => FishingDifficulty.moderate,
      };

  static bool _boolValue(Object? value) =>
      value == true || value?.toString().toLowerCase() == 'true';

  String get trendText {
    if (!hasKnownTrend) return 'Unknown';
    return switch (trend) {
      WaterTrend.rising => 'În creștere',
      WaterTrend.falling => 'În scădere',
      WaterTrend.stable => 'Stabil',
    };
  }
}
