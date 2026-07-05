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
        'apparent_temperature',
        'relative_humidity_2m',
        'weather_code',
        'wind_speed_10m',
        'wind_direction_10m',
        'pressure_msl',
      ].join(','),
      'daily': [
        'weather_code',
        'temperature_2m_max',
        'temperature_2m_min',
        'sunrise',
        'sunset',
      ].join(','),
      'forecast_days': '3',
      'timezone': 'auto',
    });

    final payload = await apiClient
        .get(uri.toString())
        .timeout(const Duration(seconds: 12));

    if (payload is! Map<String, dynamic> ||
        payload['current'] is! Map<String, dynamic> ||
        payload['daily'] is! Map<String, dynamic>) {
      throw const WeatherRepositoryException('Invalid weather response');
    }

    final current = payload['current'] as Map<String, dynamic>;
    final temperature = _number(current['temperature_2m']);
    final feelsLike = _number(current['apparent_temperature']);
    final humidity = _number(current['relative_humidity_2m']);
    final weatherCode = _number(current['weather_code'])?.round();
    final windSpeed = _number(current['wind_speed_10m']);
    final windDirection = _number(current['wind_direction_10m']);
    final pressure = _number(current['pressure_msl']);
    final forecast = _forecast(payload['daily'] as Map<String, dynamic>);

    if (temperature == null ||
        humidity == null ||
        weatherCode == null ||
        windSpeed == null ||
        windDirection == null ||
        forecast.length < 3) {
      throw const WeatherRepositoryException('Incomplete weather response');
    }

    return WeatherData(
      temperature: temperature,
      feelsLike: feelsLike,
      condition: _conditionForCode(weatherCode),
      humidity: humidity,
      windSpeed: windSpeed,
      windDirectionDegrees: windDirection,
      pressure: pressure,
      observedAt:
          DateTime.tryParse(current['time']?.toString() ?? '') ??
          DateTime.now(),
      forecast: forecast,
      sunrise: forecast.first.sunrise,
      sunset: forecast.first.sunset,
      moonPhase: _moonPhase(forecast.first.date),
      fishingActivity: _fishingActivity(forecast.first.date),
    );
  }

  static List<WeatherForecastDay> _forecast(Map<String, dynamic> daily) {
    final dates = _list(daily['time']);
    final codes = _list(daily['weather_code']);
    final minimums = _list(daily['temperature_2m_min']);
    final maximums = _list(daily['temperature_2m_max']);
    final sunrises = _list(daily['sunrise']);
    final sunsets = _list(daily['sunset']);
    final length = [
      dates.length,
      codes.length,
      minimums.length,
      maximums.length,
      sunrises.length,
      sunsets.length,
    ].reduce((a, b) => a < b ? a : b);

    return List.generate(length, (index) {
      final date = DateTime.tryParse(dates[index].toString());
      final code = _number(codes[index])?.round();
      final minimum = _number(minimums[index]);
      final maximum = _number(maximums[index]);
      final sunrise = DateTime.tryParse(sunrises[index].toString());
      final sunset = DateTime.tryParse(sunsets[index].toString());
      if (date == null ||
          code == null ||
          minimum == null ||
          maximum == null ||
          sunrise == null ||
          sunset == null) {
        return null;
      }
      return WeatherForecastDay(
        date: date,
        minimumTemperature: minimum,
        maximumTemperature: maximum,
        condition: _conditionForCode(code),
        sunrise: sunrise,
        sunset: sunset,
      );
    }).whereType<WeatherForecastDay>().toList(growable: false);
  }

  static List<Object?> _list(Object? value) =>
      value is List ? value : const <Object?>[];

  static double _lunarCycle(DateTime date) {
    final knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);
    final days = date.toUtc().difference(knownNewMoon).inMinutes / 1440;
    return ((days / 29.53058867) % 1 + 1) % 1;
  }

  static String _moonPhase(DateTime date) {
    final phase = _lunarCycle(date);
    if (phase < .0625 || phase >= .9375) return 'New moon';
    if (phase < .1875) return 'Waxing crescent';
    if (phase < .3125) return 'First quarter';
    if (phase < .4375) return 'Waxing gibbous';
    if (phase < .5625) return 'Full moon';
    if (phase < .6875) return 'Waning gibbous';
    if (phase < .8125) return 'Last quarter';
    return 'Waning crescent';
  }

  static FishingActivity _fishingActivity(DateTime date) {
    final phase = _lunarCycle(date);
    final distance = [
      phase,
      (phase - .5).abs(),
      1 - phase,
    ].reduce((a, b) => a < b ? a : b);
    if (distance <= .06) return FishingActivity.excellent;
    if (distance <= .13) return FishingActivity.good;
    if (distance <= .20) return FishingActivity.fair;
    return FishingActivity.poor;
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
