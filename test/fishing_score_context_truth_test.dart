import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 22, 12);
  final weather = _weather(now);
  final service = FishingScoreService();

  test('UK GPS without eligible Water keeps Water unavailable', () {
    final score = service.calculateFrom(
      weather: weather,
      weatherAvailable: true,
      waterAvailable: false,
      localTime: now,
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(score.hasEnoughData, isTrue);
    expect(score.score, 72.5);
    expect(score.confidence, 25);
    expect(
      score.missingFactors,
      contains('Score calculated without live water data.'),
    );
  });

  test('Astronomy uses GPS coordinates when there is no station', () {
    final score = service.calculateFrom(
      weather: weather,
      weatherAvailable: true,
      waterAvailable: false,
      localTime: now,
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(score.goldenHour, isNot('Location required'));
  });

  test('stale Weather receives reduced confidence', () {
    final fresh = service.calculateFrom(
      weather: weather,
      weatherAvailable: true,
      localTime: now,
      latitude: 51.4545,
      longitude: -2.5879,
    );
    final stale = service.calculateFrom(
      weather: weather,
      weatherAvailable: true,
      weatherStale: true,
      localTime: now,
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(fresh.confidence, 25);
    expect(stale.confidence, 12);
    expect(
      stale.missingFactors,
      contains('Weather data is stale and confidence is reduced.'),
    );
  });

  test('empty/global Community grants no Community or Catches confidence', () {
    final score = service.calculateFrom(
      weather: weather,
      posts: const [],
      weatherAvailable: true,
      communityAvailable: false,
      catchesAvailable: false,
      localTime: now,
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(score.confidence, 25);
    expect(
      score.missingFactors,
      contains('Score calculated without active community reports.'),
    );
    expect(
      score.missingFactors,
      contains('Score calculated without recent catch data.'),
    );
  });

  test('distant posts are excluded and local reports/catches are included', () {
    final posts = [
      _report('bristol-report', 51.46, -2.58, now),
      _catch('bristol-catch', 51.45, -2.59, now),
      _report('bazias-report', 44.82, 21.39, now),
    ];
    final local = filterFishingScoreLocalPosts(
      posts,
      latitude: 51.4545,
      longitude: -2.5879,
    );

    expect(
      local.map((post) => post.id),
      containsAll(['bristol-report', 'bristol-catch']),
    );
    expect(local.map((post) => post.id), isNot(contains('bazias-report')));

    final score = service.calculateFrom(
      weather: weather,
      posts: local,
      weatherAvailable: true,
      communityAvailable: local.any((post) => post.isActiveReport),
      catchesAvailable: local.any(
        (post) => post.type == CommunityPostType.catchPost,
      ),
      localTime: now,
      latitude: 51.4545,
      longitude: -2.5879,
    );
    expect(score.confidence, 75);
  });

  test('Hydro entity without measured station keeps Water unknown', () {
    const hydro = SelectedContext(
      countryCode: 'RO',
      locationName: 'Frunzaru',
      latitude: 44.333,
      longitude: 24.617,
      hydropowerPlantId: 'frunzaru',
    );
    final context = resolveFluviContext(
      selected: hydro,
      physicalLocation: null,
    )!;
    final score = service.calculateFrom(
      weather: weather,
      weatherAvailable: true,
      waterAvailable: false,
      localTime: now,
      latitude: context.latitude,
      longitude: context.longitude,
    );

    expect(context.entityType, 'hydropower');
    expect(
      score.missingFactors,
      contains('Score calculated without live water data.'),
    );
  });
}

WeatherData _weather(DateTime now) => WeatherData(
  temperature: 18,
  condition: 'Clear',
  humidity: 65,
  windSpeed: 8,
  windGusts: 12,
  windDirectionDegrees: 180,
  precipitationProbability: 10,
  cloudCover: 45,
  observedAt: now,
  forecast: const [],
  hourlyForecast: const [],
  moonPhase: 'Waxing',
  fishingActivity: FishingActivity.good,
);

CommunityPost _report(
  String id,
  double latitude,
  double longitude,
  DateTime now,
) => CommunityPost(
  id: id,
  userId: 'user',
  type: CommunityPostType.report,
  title: 'Activity',
  body: 'Local activity',
  createdAt: now.subtract(const Duration(hours: 1)),
  authorName: 'Angler',
  reportCategory: ReportCategory.fishActivity,
  latitude: latitude,
  longitude: longitude,
  // This fixture validates locality, not wall-clock expiry. Keep it active so
  // the contract remains deterministic when the suite runs later in the day.
  expiresAt: now.add(const Duration(days: 3650)),
);

CommunityPost _catch(
  String id,
  double latitude,
  double longitude,
  DateTime now,
) => CommunityPost(
  id: id,
  userId: 'user',
  type: CommunityPostType.catchPost,
  title: 'Pike',
  body: 'Catch',
  createdAt: now.subtract(const Duration(hours: 1)),
  authorName: 'Angler',
  latitude: latitude,
  longitude: longitude,
);
