import 'dart:developer' as developer;

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
        'wind_gusts_10m',
        'wind_direction_10m',
        'cloud_cover',
        'pressure_msl',
        'precipitation',
        'is_day',
      ].join(','),
      'hourly': [
        'temperature_2m',
        'apparent_temperature',
        'relative_humidity_2m',
        'precipitation_probability',
        'cloud_cover',
        'wind_speed_10m',
        'wind_gusts_10m',
        'wind_direction_10m',
        'pressure_msl',
        'weather_code',
        'precipitation',
        'visibility',
        'dew_point_2m',
        'uv_index',
        'is_day',
      ].join(','),
      'daily': [
        'weather_code',
        'temperature_2m_max',
        'temperature_2m_min',
        'sunrise',
        'sunset',
        'precipitation_probability_max',
        'precipitation_sum',
        'uv_index_max',
      ].join(','),
      'forecast_days': '7',
      'timezone': 'auto',
    });

    final payload = await _fetch(uri);

    if (payload is! Map<String, dynamic> ||
        payload['current'] is! Map<String, dynamic> ||
        payload['hourly'] is! Map<String, dynamic> ||
        payload['daily'] is! Map<String, dynamic>) {
      _logApiError(const WeatherRepositoryException('Invalid response'));
      throw const WeatherRepositoryException('Invalid weather response');
    }

    final current = payload['current'] as Map<String, dynamic>;
    final temperature = _number(current['temperature_2m']);
    final feelsLike = _number(current['apparent_temperature']);
    final humidity = _number(current['relative_humidity_2m']);
    final weatherCode = _number(current['weather_code'])?.round();
    final windSpeed = _number(current['wind_speed_10m']);
    final windGusts = _number(current['wind_gusts_10m']);
    final windDirection = _number(current['wind_direction_10m']);
    final cloudCover = _number(current['cloud_cover']);
    final pressure = _number(current['pressure_msl']);
    final currentPrecipitation = _number(current['precipitation']);
    final currentIsDay = _number(current['is_day']);
    final observedAt =
        DateTime.tryParse(current['time']?.toString() ?? '') ?? DateTime.now();
    final hourly = _hourly(payload['hourly'] as Map<String, dynamic>);
    final currentHour = _closestHour(hourly, observedAt);
    final forecast = _forecast(payload['daily'] as Map<String, dynamic>);

    if (temperature == null ||
        humidity == null ||
        weatherCode == null ||
        windSpeed == null ||
        windGusts == null ||
        windDirection == null ||
        cloudCover == null ||
        currentHour == null ||
        forecast.length < 7) {
      _logApiError(const WeatherRepositoryException('Incomplete response'));
      throw const WeatherRepositoryException('Incomplete weather response');
    }

    return WeatherData(
      temperature: temperature,
      feelsLike: feelsLike,
      condition: _conditionForCode(weatherCode),
      humidity: humidity,
      windSpeed: windSpeed,
      windGusts: windGusts,
      windDirectionDegrees: windDirection,
      precipitationProbability: currentHour.precipitationProbability,
      cloudCover: cloudCover,
      pressure: pressure,
      precipitation: currentPrecipitation ?? currentHour.precipitation,
      visibility: currentHour.visibility,
      dewPoint: currentHour.dewPoint,
      uvIndex: currentHour.uvIndex,
      isDay: currentIsDay == null ? currentHour.isDay : currentIsDay >= 0.5,
      observedAt: observedAt,
      forecast: forecast,
      hourlyForecast: hourly
          .where((hour) => !hour.time.isBefore(observedAt))
          .take(24)
          .toList(growable: false),
      sunrise: forecast.first.sunrise,
      sunset: forecast.first.sunset,
      moonPhase: _moonPhase(forecast.first.date),
      fishingActivity: _fishingActivity(forecast.first.date),
    );
  }

  Future<Object?> _fetch(Uri uri) async {
    try {
      return await apiClient
          .get(uri.toString())
          .timeout(const Duration(seconds: 12));
    } on Object catch (error, stackTrace) {
      _logApiError(error, stackTrace);
      rethrow;
    }
  }

  static List<WeatherForecastHour> _hourly(Map<String, dynamic> hourly) {
    final times = _list(hourly['time']);
    final temperatures = _list(hourly['temperature_2m']);
    final feelsLike = _list(hourly['apparent_temperature']);
    final humidities = _list(hourly['relative_humidity_2m']);
    final precipitation = _list(hourly['precipitation_probability']);
    final cloudCover = _list(hourly['cloud_cover']);
    final windSpeeds = _list(hourly['wind_speed_10m']);
    final windGusts = _list(hourly['wind_gusts_10m']);
    final windDirections = _list(hourly['wind_direction_10m']);
    final pressures = _list(hourly['pressure_msl']);
    final weatherCodes = _list(hourly['weather_code']);
    final precipitationAmounts = _list(hourly['precipitation']);
    final visibilities = _list(hourly['visibility']);
    final dewPoints = _list(hourly['dew_point_2m']);
    final uvIndexes = _list(hourly['uv_index']);
    final isDayValues = _list(hourly['is_day']);
    final length = [
      times.length,
      temperatures.length,
      feelsLike.length,
      humidities.length,
      precipitation.length,
      cloudCover.length,
      windSpeeds.length,
      windGusts.length,
      windDirections.length,
      pressures.length,
      weatherCodes.length,
    ].reduce((a, b) => a < b ? a : b);

    return List.generate(length, (index) {
      final time = DateTime.tryParse(times[index].toString());
      final temperature = _number(temperatures[index]);
      final apparent = _number(feelsLike[index]);
      final humidity = _number(humidities[index]);
      final rainChance = _number(precipitation[index]);
      final clouds = _number(cloudCover[index]);
      final wind = _number(windSpeeds[index]);
      final gusts = _number(windGusts[index]);
      final direction = _number(windDirections[index]);
      final pressure = _number(pressures[index]);
      final weatherCode = _number(weatherCodes[index])?.round();
      final precipitationAmount = _numberAt(precipitationAmounts, index);
      final visibility = _numberAt(visibilities, index);
      final dewPoint = _numberAt(dewPoints, index);
      final uvIndex = _numberAt(uvIndexes, index);
      final isDayRaw = _numberAt(isDayValues, index);
      if (time == null ||
          temperature == null ||
          apparent == null ||
          humidity == null ||
          rainChance == null ||
          clouds == null ||
          wind == null ||
          gusts == null ||
          direction == null ||
          pressure == null ||
          weatherCode == null) {
        return null;
      }
      return WeatherForecastHour(
        time: time,
        temperature: temperature,
        feelsLike: apparent,
        humidity: humidity,
        precipitationProbability: rainChance,
        cloudCover: clouds,
        windSpeed: wind,
        windGusts: gusts,
        windDirectionDegrees: direction,
        pressure: pressure,
        condition: _conditionForCode(weatherCode),
        precipitation: precipitationAmount,
        visibility: visibility,
        dewPoint: dewPoint,
        uvIndex: uvIndex,
        isDay: isDayRaw == null ? null : isDayRaw >= 0.5,
      );
    }).whereType<WeatherForecastHour>().toList(growable: false);
  }

  static WeatherForecastHour? _closestHour(
    List<WeatherForecastHour> hours,
    DateTime observedAt,
  ) {
    if (hours.isEmpty) return null;
    return hours.reduce((closest, candidate) {
      final closestDifference = closest.time.difference(observedAt).abs();
      final candidateDifference = candidate.time.difference(observedAt).abs();
      return candidateDifference < closestDifference ? candidate : closest;
    });
  }

  static void _logApiError(Object error, [StackTrace? stackTrace]) {
    developer.log(
      'Open-Meteo request failed',
      name: 'AIFishMap.Weather',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static List<WeatherForecastDay> _forecast(Map<String, dynamic> daily) {
    final dates = _list(daily['time']);
    final codes = _list(daily['weather_code']);
    final minimums = _list(daily['temperature_2m_min']);
    final maximums = _list(daily['temperature_2m_max']);
    final sunrises = _list(daily['sunrise']);
    final sunsets = _list(daily['sunset']);
    final precipitationProbabilityMax = _list(
      daily['precipitation_probability_max'],
    );
    final precipitationSums = _list(daily['precipitation_sum']);
    final uvIndexMax = _list(daily['uv_index_max']);
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
        precipitationProbabilityMax: _numberAt(
          precipitationProbabilityMax,
          index,
        ),
        precipitationSum: _numberAt(precipitationSums, index),
        uvIndexMax: _numberAt(uvIndexMax, index),
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

  static double? _numberAt(List<Object?> values, int index) {
    if (index < 0 || index >= values.length) return null;
    return _number(values[index]);
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
