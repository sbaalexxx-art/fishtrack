enum WaterTrend { rising, falling, stable }

class Station {
  final String id;
  final String name;
  final String river;

  final double level;

  final WaterTrend trend;

  final double latitude;
  final double longitude;

  final DateTime lastUpdate;

  const Station({
    required this.id,
    required this.name,
    required this.river,
    required this.level,
    required this.trend,
    required this.latitude,
    required this.longitude,
    required this.lastUpdate,
  });

  String get trendText {
    switch (trend) {
      case WaterTrend.rising:
        return "În creștere";

      case WaterTrend.falling:
        return "În scădere";

      case WaterTrend.stable:
        return "Stabil";
    }
  }
}
