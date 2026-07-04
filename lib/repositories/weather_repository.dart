import '../core/network/api_client.dart';
import '../models/weather.dart';

class WeatherRepository {
  const WeatherRepository({this.apiClient = const ApiClient()});

  final ApiClient apiClient;

  Future<WeatherData> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': [
        'temperature_2m',
        'relative_humidity_2m',
        'weather_code',
        'wind_speed_10m',
      ].join(','),
      'timezone': 'auto',
    });

    final payload = await apiClient
        .get(uri.toString())
        .timeout(const Duration(seconds: 12));

    if (payload is! Map<String, dynamic> ||
        payload['current'] is! Map<String, dynamic>) {
      throw const WeatherRepositoryException('Invalid weather response');
    }

    final current = payload['current'] as Map<String, dynamic>;
    final temperature = _number(current['temperature_2m']);
    final humidity = _number(current['relative_humidity_2m']);
    final weatherCode = _number(current['weather_code'])?.round();
    final windSpeed = _number(current['wind_speed_10m']);

    if (temperature == null ||
        humidity == null ||
        weatherCode == null ||
        windSpeed == null) {
      throw const WeatherRepositoryException('Incomplete weather response');
    }

    return WeatherData(
      temperature: temperature,
      condition: _conditionForCode(weatherCode),
      humidity: humidity,
      windSpeed: windSpeed,
      observedAt:
          DateTime.tryParse(current['time']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static double? _number(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static String _conditionForCode(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 2) return 'Partly cloudy';
    if (code == 3) return 'Overcast';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain showers';
    if (code == 85 || code == 86) return 'Snow showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Unknown';
  }
}

class WeatherRepositoryException implements Exception {
  const WeatherRepositoryException(this.message);

  final String message;
}
