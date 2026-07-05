import '../models/station.dart';
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
      bestTime = '--:--',
      confidence = 0;

  final double? score;
  final FishingScoreRating? rating;
  final String recommendation;
  final String explanation;
  final List<String> positiveFactors;
  final List<String> negativeFactors;
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
    List<CommunityPost> posts = const [];
    var communityAvailable = true;

    try {
      station = await _waterService.getNearestStation(
        fallbackStation: fallbackStation,
      );
    } on Exception {
      station = fallbackStation;
    }
    try {
      weather = await _weatherService.getCurrentWeather(
        fallbackStation: station,
      );
    } on Exception {
      return const FishingScoreResult.notEnough();
    }
    try {
      posts = await _communityService.getFeed();
    } on Exception {
      communityAvailable = false;
    }

    return calculateFrom(
      weather: weather,
      station: station,
      posts: posts,
      communityAvailable: communityAvailable,
      localTime: DateTime.now(),
    );
  }

  FishingScoreResult calculateFrom({
    required WeatherData weather,
    Station? station,
    List<CommunityPost> posts = const [],
    bool communityAvailable = true,
    required DateTime localTime,
  }) {
    final factors = <_Factor>[
      _temperatureFactor(weather.temperature),
      _windFactor(weather.windSpeed, weather.windDirectionLabel),
      _conditionFactor(weather.condition),
      _solunarFactor(weather.fishingActivity),
      _timeFactor(localTime.hour),
      _seasonFactor(localTime.month),
    ];
    if (weather.pressure != null) {
      factors.add(_pressureFactor(weather.pressure!));
    }

    final hasWater =
        station != null && station.lastUpdate.millisecondsSinceEpoch > 0;
    if (hasWater) {
      factors.add(_waterTrendFactor(station.trend));
      factors.add(_waterLevelFactor(station.level));
    }
    if (communityAvailable) {
      factors.addAll(_communityFactors(posts, localTime));
    }

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
    final confidence = _confidence(
      weather: weather,
      station: station,
      communityAvailable: communityAvailable,
      localTime: localTime,
    );
    if (confidence < 35) return const FishingScoreResult.notEnough();

    return FishingScoreResult(
      score: score,
      rating: rating,
      recommendation: score >= 55 ? 'Merită să mergi' : 'Mai bine aștepți',
      explanation: _explanation(positives, negatives),
      positiveFactors: positives.map((factor) => factor.text).take(4).toList(),
      negativeFactors: negatives.map((factor) => factor.text).take(4).toList(),
      bestTime: _bestTime(localTime.month),
      confidence: confidence,
    );
  }

  _Factor _temperatureFactor(double value) {
    if (value >= 10 && value <= 22) {
      return const _Factor(8, 'Comfortable temperature');
    }
    if (value < 2 || value > 32) {
      return const _Factor(-9, 'Extreme temperature');
    }
    return const _Factor(1, 'Usable temperature');
  }

  _Factor _windFactor(double speed, String direction) {
    if (speed >= 3 && speed <= 18) {
      return _Factor(7, 'Moderate $direction wind');
    }
    if (speed > 30) {
      return _Factor(-12, 'Strong $direction wind');
    }
    if (speed > 22) {
      return _Factor(-6, 'Difficult $direction wind');
    }
    return _Factor(1, 'Light $direction wind');
  }

  _Factor _conditionFactor(String condition) {
    final value = condition.toLowerCase();
    if (value.contains('thunder') || value.contains('storm')) {
      return const _Factor(-18, 'Thunderstorm conditions');
    }
    if (value.contains('cloud') || value.contains('overcast')) {
      return const _Factor(6, 'Cloud cover');
    }
    if (value.contains('rain') || value.contains('snow')) {
      return const _Factor(-5, 'Precipitation');
    }
    return _Factor(1, condition);
  }

  _Factor _pressureFactor(double pressure) {
    if (pressure >= 1010 && pressure <= 1024) {
      return const _Factor(4, 'Moderate air pressure');
    }
    if (pressure < 990 || pressure > 1040) {
      return const _Factor(-5, 'Extreme air pressure');
    }
    return const _Factor(0, 'Air pressure available');
  }

  _Factor _solunarFactor(FishingActivity activity) => switch (activity) {
    FishingActivity.excellent => const _Factor(
      10,
      'Excellent solunar activity',
    ),
    FishingActivity.good => const _Factor(6, 'Good solunar activity'),
    FishingActivity.fair => const _Factor(1, 'Fair solunar activity'),
    FishingActivity.poor => const _Factor(-5, 'Poor solunar activity'),
  };

  _Factor _waterTrendFactor(WaterTrend trend) => switch (trend) {
    WaterTrend.stable => const _Factor(7, 'Stable water trend'),
    WaterTrend.rising => const _Factor(1, 'Rising water trend'),
    WaterTrend.falling => const _Factor(-5, 'Falling water trend'),
  };

  _Factor _waterLevelFactor(double level) => level > 0
      ? const _Factor(1, 'Official water level available')
      : const _Factor(-2, 'Water level is very low');

  List<_Factor> _communityFactors(List<CommunityPost> posts, DateTime now) {
    final recent = posts.where(
      (post) =>
          now.difference(post.createdAt).abs() <= const Duration(hours: 24),
    );
    final catches = recent
        .where((post) => post.type == CommunityPostType.catchPost)
        .length;
    final reports = recent.where((post) => post.isActiveReport).toList();
    final factors = <_Factor>[];
    if (catches > 0) {
      factors.add(
        _Factor(
          (catches * 2).clamp(2, 8).toDouble(),
          '$catches recent catches',
        ),
      );
    }
    final good = reports
        .where(
          (post) =>
              post.reportCategory == ReportCategory.goodFishing ||
              post.reportCategory == ReportCategory.fishActivity,
        )
        .length;
    final poor = reports
        .where(
          (post) =>
              post.reportCategory == ReportCategory.poorFishing ||
              post.reportCategory == ReportCategory.strongCurrent ||
              post.reportCategory == ReportCategory.accessBlocked,
        )
        .length;
    if (good > 0) {
      factors.add(
        _Factor(
          (good * 2).clamp(2, 6).toDouble(),
          '$good positive community reports',
        ),
      );
    }
    if (poor > 0) {
      factors.add(
        _Factor(-(poor * 3).clamp(3, 9).toDouble(), '$poor caution reports'),
      );
    }
    return factors;
  }

  _Factor _timeFactor(int hour) =>
      (hour >= 5 && hour <= 9) || (hour >= 17 && hour <= 21)
      ? const _Factor(7, 'Dawn or dusk feeding window')
      : const _Factor(0, 'Current time of day');

  _Factor _seasonFactor(int month) => switch (month) {
    >= 3 && <= 5 => const _Factor(4, 'Spring season'),
    >= 9 && <= 11 => const _Factor(4, 'Autumn season'),
    >= 6 && <= 8 => const _Factor(1, 'Summer season'),
    _ => const _Factor(-3, 'Winter season'),
  };

  int _confidence({
    required WeatherData weather,
    required Station? station,
    required bool communityAvailable,
    required DateTime localTime,
  }) {
    var value = 55;
    if (weather.pressure != null) value += 5;
    if (station != null && station.lastUpdate.millisecondsSinceEpoch > 0) {
      value += 20;
    }
    if (communityAvailable) {
      value += 10;
    }
    value += 10; // Time, season and solunar data are available locally.
    final weatherAge = localTime.difference(weather.observedAt.toLocal()).abs();
    if (weatherAge > const Duration(hours: 3)) value -= 15;
    if (station != null &&
        localTime.difference(station.lastUpdate.toLocal()).abs() >
            const Duration(days: 1)) {
      value -= 15;
    }
    return value.clamp(0, 100);
  }

  String _explanation(List<_Factor> positive, List<_Factor> negative) {
    if (positive.isEmpty && negative.isEmpty) return 'Not enough data yet';
    final parts = <String>[];
    if (positive.isNotEmpty) {
      parts.add('Helps: ${positive.first.text.toLowerCase()}');
    }
    if (negative.isNotEmpty) {
      parts.add('Watch: ${negative.first.text.toLowerCase()}');
    }
    return '${parts.join('. ')}.';
  }

  String _bestTime(int month) => switch (month) {
    >= 6 && <= 8 => '05:00 - 09:00',
    == 12 || <= 2 => '08:00 - 11:00',
    _ => '06:00 - 10:00',
  };
}

class _Factor {
  const _Factor(this.points, this.text);
  final double points;
  final String text;
}
