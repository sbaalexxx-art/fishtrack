import 'dart:async';
import 'dart:io';

import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/services/weather_service.dart';
import 'package:fishtrack/widgets/home/home_map.dart';
import 'package:fishtrack/widgets/home/home_map_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('Home mini-map runtime excludes monitoring-station infrastructure', () {
    expect(MapOverlay.values, [
      MapOverlay.communityReports,
      MapOverlay.recentCatches,
    ]);

    final rendererSource = File(
      'lib/widgets/home/home_map_renderer.dart',
    ).readAsStringSync();
    expect(rendererSource, isNot(contains('_stationAnnotationManager')));
    expect(rendererSource, isNot(contains('_stationTapEvents')));
    expect(rendererSource, isNot(contains("'type': 'water_station'")));
    expect(rendererSource, contains('_reportAnnotationManager'));
    expect(rendererSource, contains('_locationContextAnnotationManager'));
  });

  test('Home renderer retains location and exploration context inputs', () {
    const renderer = HomeMapRenderer(
      reports: [],
      initialCamera: LatLng(51.4545, -2.5879),
      currentLocation: LatLng(51.4545, -2.5879),
      explorationCenter: LatLng(44.8167, 21.3944),
    );

    expect(renderer.currentLocation, const LatLng(51.4545, -2.5879));
    expect(renderer.explorationCenter, const LatLng(44.8167, 21.3944));
    expect(renderer.overlays, const {MapOverlay.communityReports});
  });

  testWidgets('approved Home renders the canonical Bento hierarchy at 390px', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    expect(find.byKey(const ValueKey('canonical-home')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('commercial-home-context-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('commercial-home-map-hero')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('commercial-home-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-map-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-map-locate')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-ask-fluvi')), findsOneWidget);
    expect(find.byKey(const ValueKey('commercial-water-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('commercial-weather-card')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('commercial-score-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('commercial-community-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('commercial-reports-card')),
      findsOneWidget,
    );

    expect(find.byKey(const ValueKey('home-more-menu-action')), findsNothing);
    expect(find.text('Drobeta-Turnu Severin'), findsOneWidget);
    expect(find.textContaining('Dunărea'), findsWidgets);
    expect(find.text('690'), findsOneWidget);
    expect(find.text('22°'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    expect(find.text('Acces blocat'), findsOneWidget);

    expect(
      tester.getSize(find.byKey(const ValueKey('commercial-home-map-hero'))),
      const Size(358, 274),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('390x844 Home shows the final card without an initial scroll', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final report = tester.getRect(
      find.byKey(const ValueKey('commercial-reports-card')),
    );
    expect(scrollable.position.pixels, 0);
    expect(report.bottom, lessThanOrEqualTo(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home mini-map and context header stay non-navigating previews', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));

    var selectedTab = -1;
    await tester.pumpWidget(
      _testApp(
        dataSource: _FakeCommercialHomeDataSource(_snapshot()),
        onNavigate: (index) => selectedTab = index,
      ),
    );
    await _settleHome(tester);

    await tester.tap(
      find.byKey(const ValueKey('commercial-home-context-header')),
    );
    await tester.pump();
    expect(selectedTab, -1);

    await tester.tap(find.byKey(const ValueKey('commercial-home-map')));
    await tester.pump();
    expect(selectedTab, -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Commercial Home manual refresh remains a forced reload', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final source = _RecordingCommercialHomeDataSource(_snapshot());

    await tester.pumpWidget(_testApp(dataSource: source));
    await tester.pumpAndSettle();
    expect(source.forceRefreshes, [false]);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(source.forceRefreshes, [false, true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote station selection does not replace Home GPS header', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final source = _MutableCommercialHomeDataSource(_snapshot());
    addTearDown(source.dispose);

    await tester.pumpWidget(_testApp(dataSource: source));
    await _settleHome(tester);
    expect(find.text('Drobeta-Turnu Severin'), findsOneWidget);

    final now = DateTime.now().toUtc();
    final station = Station(
      id: 'bazias',
      name: 'Baziaș',
      river: 'Timiș',
      level: 121,
      trend: WaterTrend.stable,
      latitude: 44.816,
      longitude: 21.39,
      lastUpdate: now,
      hasWaterLevel: true,
      hasKnownTrend: true,
      waterLevelSource: 'AFDJ',
    );
    source.select(
      CommercialHomeSnapshot(
        station: station,
        water: null,
        weather: null,
        score: null,
        communityPosts: const [],
        loadedAt: now,
        currentLocation: source.current.currentLocation,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Drobeta-Turnu Severin'), findsOneWidget);
    expect(find.textContaining('Timiș'), findsWidgets);
    final context = tester.element(find.byType(CommercialHomePage));
    final container = ProviderScope.containerOf(context, listen: false);
    expect(container.read(selectedContextProvider)?.stationId, 'bazias');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home presents truthful 24h water delta and polished compact weather',
    (tester) async {
      _configurePhone(tester, const Size(390, 844));

      await tester.pumpWidget(
        _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
      );
      await _settleHome(tester);

      expect(find.text('−12 cm / 24h · În scădere'), findsOneWidget);
      expect(find.text('AFDJ · acum 42 min'), findsOneWidget);
      expect(find.text('SV 11 km/h'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home never presents a sparse five-day delta as a daily delta', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    final baseline = _snapshot();
    final water = baseline.water!;
    final sparse = CommercialHomeSnapshot(
      station: baseline.station,
      water: WaterUiResult(
        latestReading: water.latestReading,
        previousReading: water.previousReading,
        history: water.history,
        source: water.source,
        sourceName: 'afdj',
        measurementTimestamp: water.measurementTimestamp,
        dataAge: const Duration(days: 10),
        isStale: true,
        status: water.status,
        safeDiagnosticMessage: water.safeDiagnosticMessage,
        deltaCm: -6,
        comparisonDuration: const Duration(days: 5),
        trend: water.trend,
        hasEnoughHistory: true,
      ),
      weather: baseline.weather,
      score: baseline.score,
      communityPosts: baseline.communityPosts,
      loadedAt: baseline.loadedAt,
      currentLocation: baseline.currentLocation,
    );

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(sparse)),
    );
    await _settleHome(tester);

    expect(find.text('Trend în scădere'), findsOneWidget);
    expect(find.text('Date insuficiente pentru Δ24h'), findsOneWidget);
    expect(find.textContaining('/ 5d'), findsNothing);
    expect(find.text('AFDJ · acum 10 zile'), findsOneWidget);
    expect(find.text('VECHI'), findsNothing);
    expect(find.text('STALE'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bento Home reflows safely at 360px and textScale 1.3', (
    tester,
  ) async {
    _configurePhone(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('commercial-home-map-hero')))
          .width,
      328,
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('commercial-reports-card')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bento Home remains scrollable without overflow at 200% text', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('commercial-reports-card')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bento Home narrow-width fallback has no layout overflow', (
    tester,
  ) async {
    _configurePhone(tester, const Size(320, 700));

    await tester.pumpWidget(
      _testApp(dataSource: _FakeCommercialHomeDataSource(_snapshot())),
    );
    await _settleHome(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('commercial-home-map-hero')))
          .width,
      288,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bento Home never fabricates live values when data is absent', (
    tester,
  ) async {
    _configurePhone(tester, const Size(390, 844));

    await tester.pumpWidget(
      _testApp(
        dataSource: _FakeCommercialHomeDataSource(
          CommercialHomeSnapshot(
            station: null,
            water: null,
            weather: null,
            score: null,
            communityPosts: const [],
            loadedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await _settleHome(tester);

    expect(find.text('214'), findsNothing);
    expect(find.text('18°'), findsNothing);
    expect(find.text('76'), findsNothing);
    expect(find.text('Niciun raport activ'), findsOneWidget);
    expect(find.text('Fără semnal local recent'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _configurePhone(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settleHome(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Widget _testApp({
  required CommercialHomeDataSource dataSource,
  ValueChanged<int>? onNavigate,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      locale: const Locale('ro'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CommercialHomePage(
        onNavigate: onNavigate ?? (_) {},
        dataSource: dataSource,
        mapOverride: const ColoredBox(color: Color(0xFF12343E)),
      ),
    ),
  );
}

CommercialHomeSnapshot _snapshot() {
  final now = DateTime.now().toUtc();
  final station = Station(
    id: 'drobeta_turnu_severin',
    name: 'Drobeta-Turnu Severin',
    river: 'Dunărea',
    level: 690,
    trend: WaterTrend.falling,
    latitude: 44.625,
    longitude: 22.656,
    lastUpdate: now.subtract(const Duration(minutes: 42)),
    hasWaterLevel: true,
    hasKnownTrend: true,
    waterLevelSource: 'AFDJ',
  );
  final current = WaterLevel(
    stationId: station.id,
    value: 690,
    timestamp: now.subtract(const Duration(minutes: 42)),
    trend: WaterTrend.falling,
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    hasKnownTrend: true,
  );
  final previous = WaterLevel(
    stationId: station.id,
    value: 702,
    timestamp: now.subtract(const Duration(hours: 24)),
    trend: WaterTrend.falling,
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    hasKnownTrend: true,
  );
  final water = WaterUiResult(
    latestReading: current,
    previousReading: previous,
    history: [previous, current],
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    measurementTimestamp: current.timestamp,
    dataAge: const Duration(minutes: 42),
    isStale: false,
    status: WaterUiStatus.availableHistory,
    safeDiagnosticMessage: null,
    deltaCm: -12,
    comparisonDuration: const Duration(hours: 24),
    trend: WaterTrend.falling,
    hasEnoughHistory: true,
  );
  final weatherData = WeatherData(
    temperature: 22,
    feelsLike: 21,
    condition: 'Partly cloudy',
    humidity: 64,
    windSpeed: 11,
    windGusts: 19,
    windDirectionDegrees: 245,
    precipitationProbability: 18,
    cloudCover: 37,
    pressure: 1015,
    observedAt: now,
    forecast: const [],
    hourlyForecast: const [],
    moonPhase: 'Waxing crescent',
    fishingActivity: FishingActivity.good,
  );
  final weather = WeatherHomeResult(
    data: weatherData,
    latitude: station.latitude,
    longitude: station.longitude,
    locationSource: WeatherLocationSource.stationFallback,
    status: WeatherHomeStatus.available,
    dataTimestamp: now,
    dataAge: Duration.zero,
    isStale: false,
    safeDiagnosticMessage: null,
  );
  final score = FishingScoreResult(
    score: 78,
    rating: FishingScoreRating.good,
    recommendation: 'Condiții bune',
    explanation: 'Semnalele principale sunt favorabile.',
    positiveFactors: const ['Presiune stabilă'],
    negativeFactors: const ['Vânt moderat'],
    missingFactors: const [],
    bestTime: '18:30–20:30',
    confidence: 75,
    moonPhase: 'Waxing crescent',
    goldenHour: '18:30–20:30',
  );
  final community = CommunityPost(
    id: 'catch-local',
    userId: 'user-1',
    type: CommunityPostType.catchPost,
    title: 'Activitate mai redusă',
    body: 'Observație locală',
    createdAt: now.subtract(const Duration(minutes: 50)),
    authorName: 'Pescar local',
    latitude: 44.63,
    longitude: 22.66,
  );
  final report = CommunityPost(
    id: 'report-local',
    userId: 'user-2',
    type: CommunityPostType.report,
    title: 'Acces dificil',
    body: 'Accesul este îngreunat temporar.',
    createdAt: now.subtract(const Duration(minutes: 24)),
    authorName: 'Pescar local',
    reportCategory: ReportCategory.accessBlocked,
    latitude: 44.632,
    longitude: 22.662,
    expiresAt: now.add(const Duration(hours: 6)),
    stillValidCount: 4,
  );

  return CommercialHomeSnapshot(
    station: station,
    water: water,
    weather: weather,
    score: score,
    communityPosts: [community, report],
    loadedAt: now,
    currentLocation: CurrentDeviceLocation(
      latitude: station.latitude,
      longitude: station.longitude,
      accuracyMeters: 8,
      observedAt: now,
      label: 'Drobeta-Turnu Severin',
    ),
  );
}

class _FakeCommercialHomeDataSource implements CommercialHomeDataSource {
  const _FakeCommercialHomeDataSource(this.snapshot);

  final CommercialHomeSnapshot snapshot;

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      snapshot;
}

class _RecordingCommercialHomeDataSource implements CommercialHomeDataSource {
  _RecordingCommercialHomeDataSource(this.snapshot);

  final CommercialHomeSnapshot snapshot;
  final List<bool> forceRefreshes = [];

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async {
    forceRefreshes.add(forceRefresh);
    return snapshot;
  }
}

class _MutableCommercialHomeDataSource implements CommercialHomeDataSource {
  _MutableCommercialHomeDataSource(this._snapshot);

  CommercialHomeSnapshot _snapshot;
  CommercialHomeSnapshot get current => _snapshot;
  final StreamController<Station> _selections =
      StreamController<Station>.broadcast();

  @override
  Stream<Station> get stationSelections => _selections.stream;

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      _snapshot;

  void select(CommercialHomeSnapshot snapshot) {
    _snapshot = snapshot;
    _selections.add(snapshot.station!);
  }

  Future<void> dispose() => _selections.close();
}
