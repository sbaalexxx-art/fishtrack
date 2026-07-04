import '../models/station.dart';
import '../models/weather.dart';
import 'water_service.dart';
import 'weather_service.dart';

enum FishingScoreRating { excellent, good, fair, poor }

class FishingScoreResult {
  const FishingScoreResult({
    required this.score,
    required this.rating,
    required this.recommendation,
    required this.bestTime,
    required this.confidence,
  });

  final double score;
  final FishingScoreRating rating;
  final String recommendation;
  final String bestTime;
  final int confidence;
}

class FishingScoreService {
  FishingScoreService({
    WaterService? waterService,
    WeatherService? weatherService,
  }) : _waterService = waterService ?? WaterService(),
       _weatherService = weatherService ?? WeatherService();

  final WaterService _waterService;
  final WeatherService _weatherService;

  Future<FishingScoreResult> calculate({Station? fallbackStation}) async {
    final station = await _waterService.getNearestStation(
      fallbackStation: fallbackStation,
    );
    if (station == null) {
      throw const FishingScoreException('No water station is available.');
    }
    final weather = await _weatherService.getCurrentWeather(
      fallbackStation: station,
    );
    return calculateFrom(
      weather: weather,
      station: station,
      localTime: DateTime.now(),
    );
  }

  FishingScoreResult calculateFrom({
    required WeatherData weather,
    required Station station,
    required DateTime localTime,
  }) {
    var score = 5.0;
    score += _temperatureScore(weather.temperature);
    score += _windScore(weather.windSpeed);
    score += _weatherScore(weather.condition);
    score += _waterLevelScore(station.level);
    score += _trendScore(station.trend);
    score += _timeScore(localTime.hour);
    score += _seasonScore(localTime.month);
    score = score.clamp(0, 10).toDouble();

    final rating = switch (score) {
      >= 8 => FishingScoreRating.excellent,
      >= 6.5 => FishingScoreRating.good,
      >= 4.5 => FishingScoreRating.fair,
      _ => FishingScoreRating.poor,
    };

    return FishingScoreResult(
      score: score,
      rating: rating,
      recommendation: switch (rating) {
        FishingScoreRating.excellent => 'Fish now',
        FishingScoreRating.good => 'Good opportunity',
        FishingScoreRating.fair => 'Try sheltered water',
        FishingScoreRating.poor => 'Wait for improvement',
      },
      bestTime: _bestTime(localTime.month),
      confidence: _confidence(weather, station, localTime),
    );
  }

  double _temperatureScore(double temperature) {
    if (temperature >= 10 && temperature <= 22) return 1.4;
    if (temperature >= 5 && temperature <= 28) return .6;
    return -.8;
  }

  double _windScore(double windSpeed) {
    if (windSpeed >= 3 && windSpeed <= 18) return 1.2;
    if (windSpeed < 3 || windSpeed <= 28) return .2;
    return -1.2;
  }

  double _weatherScore(String condition) {
    final value = condition.toLowerCase();
    if (value.contains('storm') || value.contains('thunder')) return -1.5;
    if (value.contains('cloud') || value.contains('overcast')) return .7;
    if (value.contains('drizzle') || value.contains('light rain')) return .5;
    if (value.contains('rain') || value.contains('snow')) return -.5;
    return .2;
  }

  double _waterLevelScore(double level) =>
      level >= 50 && level <= 400 ? .5 : -.4;

  double _trendScore(WaterTrend trend) => switch (trend) {
    WaterTrend.stable => .9,
    WaterTrend.rising => .3,
    WaterTrend.falling => -.5,
  };

  double _timeScore(int hour) {
    if ((hour >= 5 && hour <= 9) || (hour >= 17 && hour <= 21)) return 1.1;
    if (hour >= 10 && hour <= 16) return .1;
    return .4;
  }

  double _seasonScore(int month) => switch (month) {
    >= 3 && <= 5 => .7,
    >= 9 && <= 11 => .7,
    >= 6 && <= 8 => .2,
    _ => -.4,
  };

  String _bestTime(int month) => switch (month) {
    >= 6 && <= 8 => '05:00 - 09:00',
    == 12 || <= 2 => '08:00 - 11:00',
    _ => '06:00 - 10:00',
  };

  int _confidence(WeatherData weather, Station station, DateTime localTime) {
    var confidence = 94;
    final weatherAge = localTime.difference(weather.observedAt.toLocal()).abs();
    final waterAge = localTime.difference(station.lastUpdate.toLocal()).abs();
    if (weatherAge > const Duration(hours: 1)) confidence -= 8;
    if (weatherAge > const Duration(hours: 3)) confidence -= 10;
    if (waterAge > const Duration(hours: 6)) confidence -= 8;
    if (waterAge > const Duration(days: 1)) confidence -= 12;
    return confidence.clamp(55, 96);
  }
}

class FishingScoreException implements Exception {
  const FishingScoreException(this.message);

  final String message;
}
