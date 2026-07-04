class WeatherData {
  const WeatherData({
    required this.temperature,
    required this.condition,
    required this.humidity,
    required this.windSpeed,
    required this.observedAt,
  });

  final double temperature;
  final String condition;
  final double humidity;
  final double windSpeed;
  final DateTime observedAt;
}
