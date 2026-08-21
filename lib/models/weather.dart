class WeatherData {
  const WeatherData({
    required this.temperature,
    this.feelsLike,
    required this.condition,
    required this.humidity,
    required this.windSpeed,
    required this.windGusts,
    required this.windDirectionDegrees,
    required this.precipitationProbability,
    required this.cloudCover,
    this.pressure,
    this.precipitation,
    this.visibility,
    this.dewPoint,
    this.uvIndex,
    this.isDay,
    required this.observedAt,
    required this.forecast,
    required this.hourlyForecast,
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
  final double windGusts;
  final double windDirectionDegrees;
  final double precipitationProbability;
  final double cloudCover;
  final double? pressure;
  final double? precipitation;
  final double? visibility;
  final double? dewPoint;
  final double? uvIndex;
  final bool? isDay;
  final DateTime observedAt;
  final List<WeatherForecastDay> forecast;
  final List<WeatherForecastHour> hourlyForecast;
  final DateTime? sunrise;
  final DateTime? sunset;
  final String moonPhase;
  final FishingActivity fishingActivity;

  String get windDirectionLabel => compassDirection(windDirectionDegrees);

  static String compassDirection(double degrees) {
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final normalized = ((degrees % 360) + 360) % 360;
    return labels[((normalized + 22.5) ~/ 45) % labels.length];
  }
}

class WeatherForecastHour {
  const WeatherForecastHour({
    required this.time,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.precipitationProbability,
    required this.cloudCover,
    required this.windSpeed,
    required this.windGusts,
    required this.windDirectionDegrees,
    this.pressure,
    this.condition,
    this.precipitation,
    this.visibility,
    this.dewPoint,
    this.uvIndex,
    this.isDay,
  });

  final DateTime time;
  final double temperature;
  final double feelsLike;
  final double humidity;
  final double precipitationProbability;
  final double cloudCover;
  final double windSpeed;
  final double windGusts;
  final double windDirectionDegrees;
  final double? pressure;
  final String? condition;
  final double? precipitation;
  final double? visibility;
  final double? dewPoint;
  final double? uvIndex;
  final bool? isDay;

  String get windDirectionLabel =>
      WeatherData.compassDirection(windDirectionDegrees);
}

class WeatherForecastDay {
  const WeatherForecastDay({
    required this.date,
    required this.minimumTemperature,
    required this.maximumTemperature,
    required this.condition,
    required this.sunrise,
    required this.sunset,
    this.precipitationProbabilityMax,
    this.precipitationSum,
    this.uvIndexMax,
  });

  final DateTime date;
  final double minimumTemperature;
  final double maximumTemperature;
  final String condition;
  final DateTime sunrise;
  final DateTime sunset;
  final double? precipitationProbabilityMax;
  final double? precipitationSum;
  final double? uvIndexMax;
}

enum FishingActivity { poor, fair, good, excellent }
