class WeatherData {
  const WeatherData({
    required this.temperature,
    this.feelsLike,
    required this.condition,
    required this.humidity,
    required this.windSpeed,
    required this.windDirectionDegrees,
    this.pressure,
    required this.observedAt,
    required this.forecast,
    this.sunrise,
    this.sunset,
    required this.moonPhase,
    required this.fishingActivity,
  });

  final double temperature;
  final double? feelsLike;
  final String condition;
  final double humidity;
  final double windSpeed;
  final double windDirectionDegrees;
  final double? pressure;
  final DateTime observedAt;
  final List<WeatherForecastDay> forecast;
  final DateTime? sunrise;
  final DateTime? sunset;
  final String moonPhase;
  final FishingActivity fishingActivity;

  String get windDirectionLabel {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalized = ((windDirectionDegrees % 360) + 360) % 360;
    return labels[((normalized + 22.5) ~/ 45) % labels.length];
  }
}

class WeatherForecastDay {
  const WeatherForecastDay({
    required this.date,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.condition,
    required this.sunrise,
    required this.sunset,
  });

  final DateTime date;
  final double minimumTemperature;
  final double maximumTemperature;
  final String condition;
  final DateTime sunrise;
  final DateTime sunset;
}

enum FishingActivity { poor, fair, good, excellent }
