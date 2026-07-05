import 'dart:developer' as developer;

import '../models/station.dart';
import '../models/water_level.dart';
import '../models/weather.dart';
import 'community_service.dart';
import 'water_service.dart';
import 'weather_service.dart';

enum FishingScoreRating { excellent, good, fair, poor }

abstract interface class FishingDecisionProvider {
  Future<FishingScoreResult> calculate({Station? fallbackStation});
}

class FishingScoreResult {
  const FishingScoreResult({
    required this.score,
    required this.rating,
    required this.recommendation,
    required this.explanation,
    required this.positiveFactors,
    required this.negativeFactors,
    required this.missingFactors,
    required this.bestTime,
    required this.confidence,
  });

  const FishingScoreResult.notEnough()
    : score = null,
      rating = null,
      recommendation = 'Not enough data yet',
      explanation = 'Not enough data yet',
      positiveFactors = const [],
      negativeFactors = const [],
      missingFactors = const ['No live inputs are currently available.'],
      bestTime = 'No data',
      confidence = 0;

  final double? score;
  final FishingScoreRating? rating;
  final String recommendation;
  final String explanation;
  final List<String> positiveFactors;
  final List<String> negativeFactors;
  final List<String> missingFactors;
  final String bestTime;
  final int confidence;

  bool get hasEnoughData => score != null;
}

class FishingScoreService implements FishingDecisionProvider {
  FishingScoreService({
    WaterService? waterService,
    WeatherService? weatherService,
    CommunityService? communityService,
  }) : _waterService = waterService ?? WaterService(),
       _weatherService = weatherService ?? WeatherService(),
       _communityService = communityService ?? const CommunityService();

  final WaterService _waterService;
  final WeatherService _weatherService;
  final CommunityService _communityService;

  @override
  Future<FishingScoreResult> calculate({Station? fallbackStation}) async {
    Station? station;
    WeatherData? weather;
    List<WaterLevel> history = const [];
    List<CommunityPost> posts = const [];
    var weatherAvailable = true;
    var waterAvailable = true;
    var communityAvailable = true;

    try {
      station = await _waterService.getNearestStation(
        fallbackStation: fallbackStation,
      );
      if (station == null || !station.hasWaterLevel) waterAvailable = false;
    } on Exception catch (error, stackTrace) {
      waterAvailable = false;
      station = fallbackStation;
      _logMissing('water station', error, stackTrace);
    }
    if (waterAvailable && station != null) {
      try {
        history = await _waterService.getHistory(
          station.id,
          stationName: station.name,
        );
      } on Exception catch (error, stackTrace) {
        _logMissing('water history', error, stackTrace);
      }
    }
    try {
      weather = await _weatherService.getCurrentWeather(
        fallbackStation: station,
      );
    } on Exception catch (error, stackTrace) {
      weatherAvailable = false;
      _logMissing('weather', error, stackTrace);
    }
    try {
      posts = await _communityService.getFeed();
    } on Exception catch (error, stackTrace) {
      communityAvailable = false;
      _logMissing('community reports and catches', error, stackTrace);
    }

    return _calculate(
      weather: weather,
      station: station,
      history: history,
      posts: posts,
      weatherAvailable: weatherAvailable && weather != null,
      waterAvailable: waterAvailable,
      communityAvailable: communityAvailable,
      catchesAvailable: communityAvailable,
      localTime: DateTime.now(),
    );
  }

  FishingScoreResult calculateFrom({
    required WeatherData weather,
    Station? station,
    List<WaterLevel> history = const [],
    List<CommunityPost> posts = const [],
    bool communityAvailable = true,
    bool catchesAvailable = true,
    required DateTime localTime,
  }) => _calculate(
    weather: weather,
    station: station,
    history: history,
    posts: posts,
    weatherAvailable: true,
    waterAvailable: station?.hasWaterLevel == true,
    communityAvailable: communityAvailable,
    catchesAvailable: catchesAvailable,
    localTime: localTime,
  );

  FishingScoreResult _calculate({
    required WeatherData? weather,
    required Station? station,
    required List<WaterLevel> history,
    required List<CommunityPost> posts,
    required bool weatherAvailable,
    required bool waterAvailable,
    required bool communityAvailable,
    required bool catchesAvailable,
    required DateTime localTime,
  }) {
    final factors = <_Factor>[];
    final missing = <String>[];
    if (weatherAvailable && weather != null) {
      factors.addAll(_weatherFactors(weather));
    } else {
      missing.add('Score calculated without live weather data.');
    }

    if (waterAvailable && station != null) {
      factors.addAll(_waterFactors(station, history, localTime));
      if (history.length < 2) {
        missing.add('Water history is insufficient for a verified trend.');
      }
    } else {
      missing.add('Score calculated without live water data.');
    }

    if (communityAvailable) {
      factors.addAll(_communityFactors(posts, localTime));
    } else {
      missing.add('Score calculated without active community reports.');
    }
    if (catchesAvailable) {
      factors.addAll(_catchFactors(posts, localTime));
    } else {
      missing.add('Score calculated without recent catch data.');
    }

    for (final message in missing) {
      developer.log(message, name: 'AIFishMap.FishingScore');
    }
    final confidence =
        <bool>[
          weatherAvailable,
          waterAvailable,
          communityAvailable,
          catchesAvailable,
        ].where((available) => available).length *
        25;
    if (confidence == 0) return const FishingScoreResult.notEnough();

    final score =
        (50 + factors.fold<double>(0, (sum, item) => sum + item.points))
            .clamp(0, 100)
            .toDouble();
    final rating = switch (score) {
      >= 80 => FishingScoreRating.excellent,
      >= 65 => FishingScoreRating.good,
      >= 45 => FishingScoreRating.fair,
      _ => FishingScoreRating.poor,
    };
    final positives = factors.where((factor) => factor.points > 0).toList()
      ..sort((a, b) => b.points.compareTo(a.points));
    final negatives = factors.where((factor) => factor.points < 0).toList()
      ..sort((a, b) => a.points.compareTo(b.points));
    return FishingScoreResult(
      score: score,
      rating: rating,
      recommendation: rating.name[0].toUpperCase() + rating.name.substring(1),
      explanation: _explanation(positives, negatives),
      positiveFactors: positives.map((factor) => factor.text).take(6).toList(),
      negativeFactors: negatives.map((factor) => factor.text).take(6).toList(),
      missingFactors: missing,
      bestTime: _bestTime(weather),
      confidence: confidence,
    );
  }

  List<_Factor> _weatherFactors(WeatherData weather) => [
    if (weather.temperature >= 10 && weather.temperature <= 24)
      const _Factor(7, 'Productive water-side temperature')
    else if (weather.temperature < 2 || weather.temperature > 32)
      const _Factor(-9, 'Extreme air temperature')
    else
      const _Factor(1, 'Usable air temperature'),
    if (weather.windSpeed >= 3 && weather.windSpeed <= 18)
      _Factor(6, 'Moderate ${weather.windDirectionLabel} wind')
    else if (weather.windSpeed > 30)
      _Factor(-12, 'Strong ${weather.windDirectionLabel} wind')
    else
      _Factor(1, 'Light ${weather.windDirectionLabel} wind'),
    if (weather.windGusts > 40)
      const _Factor(-10, 'Dangerous wind gusts')
    else if (weather.windGusts > 25)
      const _Factor(-5, 'Strong wind gusts'),
    if (weather.pressure case final pressure?)
      if (pressure >= 1008 && pressure <= 1024)
        const _Factor(4, 'Moderate atmospheric pressure')
      else if (pressure < 990 || pressure > 1040)
        const _Factor(-5, 'Extreme atmospheric pressure'),
    if (weather.humidity >= 45 && weather.humidity <= 85)
      const _Factor(2, 'Moderate humidity')
    else
      const _Factor(-2, 'Unfavourable humidity'),
    if (weather.precipitationProbability >= 70)
      const _Factor(-7, 'High precipitation probability')
    else if (weather.precipitationProbability <= 30)
      const _Factor(2, 'Low precipitation probability'),
    if (weather.cloudCover >= 40 && weather.cloudCover <= 85)
      const _Factor(5, 'Useful cloud cover')
    else if (weather.cloudCover < 15)
      const _Factor(-2, 'Very bright, clear conditions'),
  ];

  List<_Factor> _waterFactors(
    Station station,
    List<WaterLevel> history,
    DateTime now,
  ) {
    final factors = <_Factor>[
      const _Factor(2, 'Verified water level available'),
      switch (station.trend) {
        WaterTrend.stable => const _Factor(7, 'Stable water trend'),
        WaterTrend.rising => const _Factor(1, 'Rising water trend'),
        WaterTrend.falling => const _Factor(-5, 'Falling water trend'),
      },
    ];
    final age = now.difference(station.lastUpdate.toLocal()).abs();
    if (age > const Duration(hours: 24)) {
      factors.add(const _Factor(-7, 'Water reading is outdated'));
    } else if (age > const Duration(hours: 12)) {
      factors.add(const _Factor(-3, 'Water reading may be delayed'));
    } else {
      factors.add(_Factor(3, 'Fresh ${station.waterLevelSource} water data'));
    }
    if (history.length >= 2) {
      factors.add(const _Factor(2, 'Water history supports the trend'));
    }
    return factors;
  }

  List<_Factor> _communityFactors(List<CommunityPost> posts, DateTime now) {
    final reports = posts
        .where((post) => post.isActiveReport)
        .where((post) => now.difference(post.createdAt).abs().inHours <= 24)
        .toList();
    if (reports.isEmpty) return const [];
    final confirmations = reports.fold<int>(
      0,
      (sum, post) => sum + post.stillValidCount,
    );
    final inaccurate = reports.fold<int>(
      0,
      (sum, post) => sum + post.noLongerValidCount,
    );
    final positive = reports
        .where(
          (post) =>
              post.reportCategory == ReportCategory.goodFishing ||
              post.reportCategory == ReportCategory.fishActivity,
        )
        .length;
    final caution = reports
        .where(
          (post) =>
              post.reportCategory == ReportCategory.poorFishing ||
              post.reportCategory == ReportCategory.strongCurrent ||
              post.reportCategory == ReportCategory.accessBlocked,
        )
        .length;
    return [
      _Factor(
        (positive * 2).clamp(0, 6).toDouble(),
        '$positive positive reports',
      ),
      _Factor(
        -(caution * 3).clamp(0, 9).toDouble(),
        '$caution caution reports',
      ),
      if (confirmations > inaccurate)
        const _Factor(3, 'Community reports are mostly confirmed')
      else if (inaccurate > confirmations)
        const _Factor(-4, 'Community reports have accuracy concerns'),
    ];
  }

  List<_Factor> _catchFactors(List<CommunityPost> posts, DateTime now) {
    final catches = posts
        .where((post) => post.type == CommunityPostType.catchPost)
        .where((post) => now.difference(post.createdAt).abs().inHours <= 72)
        .toList();
    if (catches.isEmpty) return const [];
    final species = catches.map((post) => post.title).toSet().length;
    final weighed = catches.where((post) => post.weight != null).length;
    return [
      _Factor(
        (catches.length * 2).clamp(2, 8).toDouble(),
        '${catches.length} recent catches',
      ),
      _Factor(2, '$species recently reported species'),
      if (weighed > 0) _Factor(1, '$weighed catches include weight data'),
    ];
  }

  String _bestTime(WeatherData? weather) {
    final sunrise = weather?.sunrise;
    final sunset = weather?.sunset;
    if (sunrise == null || sunset == null) return 'No sunrise/sunset data';
    final difficultWeather =
        weather!.windGusts > 40 || weather.precipitationProbability >= 70;
    final start = difficultWeather
        ? sunrise.add(const Duration(minutes: 30))
        : sunrise.subtract(const Duration(minutes: 30));
    final end = difficultWeather
        ? sunrise.add(const Duration(hours: 2))
        : sunrise.add(const Duration(hours: 2, minutes: 30));
    final eveningStart = sunset.subtract(const Duration(hours: 2));
    return '${_clock(start)}–${_clock(end)} or '
        '${_clock(eveningStart)}–${_clock(sunset)}';
  }

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  String _explanation(List<_Factor> positive, List<_Factor> negative) {
    if (positive.isEmpty && negative.isEmpty) {
      return 'No strong factors detected.';
    }
    final parts = <String>[];
    if (positive.isNotEmpty) {
      parts.add('Helps: ${positive.first.text.toLowerCase()}');
    }
    if (negative.isNotEmpty) {
      parts.add('Watch: ${negative.first.text.toLowerCase()}');
    }
    return '${parts.join('. ')}.';
  }

  static void _logMissing(String input, Object error, StackTrace stackTrace) {
    developer.log(
      'Missing fishing score input: $input',
      name: 'AIFishMap.FishingScore',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _Factor {
  const _Factor(this.points, this.text);
  final double points;
  final String text;
}
