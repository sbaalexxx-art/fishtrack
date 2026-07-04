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
  final WaterBodyType waterBodyType;
  final List<String> species;
  final FishingDifficulty difficulty;
  final bool isFavorite;

  const Station({
    required this.id,
    required this.name,
    required this.river,
    required this.level,
    required this.trend,
    required this.latitude,
    required this.longitude,
    required this.lastUpdate,
    this.waterBodyType = WaterBodyType.river,
    this.species = const [],
    this.difficulty = FishingDifficulty.moderate,
    this.isFavorite = false,
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

    final trend = switch (_stringValue(json['trend'])?.toLowerCase()) {
      'rising' => WaterTrend.rising,
      'falling' => WaterTrend.falling,
      _ => WaterTrend.stable,
    };

    return Station(
      id: id,
      name: name,
      river: river,
      level: _doubleValue(json['level']) ?? 0,
      trend: trend,
      latitude: latitude,
      longitude: longitude,
      lastUpdate: _dateValue(json['last_update']),
      waterBodyType: _waterBodyType(json['water_type'] ?? json['type']),
      species: _species(json['species']),
      difficulty: _difficulty(json['difficulty']),
      isFavorite: _boolValue(json['is_favorite'] ?? json['favorite']),
    );
  }

  static String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static DateTime _dateValue(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
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

  String get trendText => switch (trend) {
    WaterTrend.rising => 'În creștere',
    WaterTrend.falling => 'În scădere',
    WaterTrend.stable => 'Stabil',
  };
}
