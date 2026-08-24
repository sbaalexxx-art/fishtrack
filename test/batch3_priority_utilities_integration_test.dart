import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/navigation/app_destination.dart';
import 'package:fishtrack/core/navigation/app_navigator.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_destination_router.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/features/shell/presentation/utilities_hub_page.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/screens/weather_page.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    AppNavigator.resetForTesting();
  });

  tearDown(AppNavigator.resetForTesting);

  test(
    'priority router keeps Water and Fluvi context while Weather stays GPS-owned',
    () {
      final station = _station();
      final source = _FakeDataSource(_snapshot());

      final water =
          FigmaDestinationRouter.page(
                AppDestination.water,
                arguments: station,
                dataSource: source,
              )
              as FigmaWaterHubPage;
      final weather = FigmaDestinationRouter.page(
        AppDestination.weather,
        arguments: station,
        dataSource: source,
      );
      final fluvi =
          FigmaDestinationRouter.page(
                AppDestination.fluvi,
                arguments: station,
                dataSource: source,
              )
              as FigmaFluviHubPage;

      expect(water.initialStation?.id, station.id);
      expect(weather, isA<WeatherPage>());
      expect((weather as WeatherPage).initialWeather, isNull);
      expect(fluvi.initialStation?.id, station.id);
      expect(identical(water.dataSource, source), isTrue);
      expect(identical(fluvi.dataSource, source), isTrue);
    },
  );

  testWidgets('canonical Home keeps Weather and Fluvi on current location', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snapshot = _snapshot();
    final source = _FakeDataSource(snapshot);
    await tester.pumpWidget(
      _app(
        CommercialHomePage(
          onNavigate: (_) {},
          dataSource: source,
          mapOverride: const ColoredBox(color: Color(0xFF12343E)),
        ),
      ),
    );
    await _pumpData(tester);

    final weatherCard = find.byKey(const ValueKey('commercial-weather-card'));
    await tester.ensureVisible(weatherCard);
    await tester.pump();
    await tester.tap(weatherCard);
    // Home passes its already-loaded Weather snapshot into canonical Weather.
    // The Hub must render that snapshot without waiting for a second GPS/API
    // round-trip. Later refreshes remain GPS-first inside WeatherPage.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final weatherRoute = find.byKey(
      AppNavigator.destinationKey(AppDestination.weather),
    );
    expect(weatherRoute, findsOneWidget);
    final weatherFinder = find.descendant(
      of: weatherRoute,
      matching: find.byType(WeatherPage),
    );
    expect(weatherFinder, findsOneWidget);
    final weatherPage = tester.widget<WeatherPage>(weatherFinder);
    expect(identical(weatherPage.initialWeather, snapshot.weather), isTrue);
    expect(
      find.descendant(of: weatherRoute, matching: find.text('18°')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(weatherRoute)).pop();
    await tester.pumpAndSettle();
    final scoreCard = find.byKey(const ValueKey('commercial-score-card'));
    await tester.ensureVisible(scoreCard);
    await tester.pump();
    await tester.tap(scoreCard);
    await tester.pumpAndSettle();
    final fluviRoute = find.byKey(
      AppNavigator.destinationKey(AppDestination.fluvi),
    );
    expect(fluviRoute, findsOneWidget);
    final fluviFinder = find.descendant(
      of: fluviRoute,
      matching: find.byType(FigmaFluviHubPage),
    );
    final fluvi = tester.widget<FigmaFluviHubPage>(fluviFinder);
    expect(fluvi.initialStation, isNull);
    expect(identical(fluvi.dataSource, source), isTrue);
  });

  testWidgets(
    'Utilities Solunar deep link stays GPS-owned without station substitution',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final source = _FakeDataSource(_snapshot());
      await tester.pumpWidget(
        _app(
          FluviAIUtilitiesHubPage(onSelectMainTab: (_) {}, dataSource: source),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(FluviAIUtilitiesHubPage));
      final container = ProviderScope.containerOf(context, listen: false);
      container
          .read(selectedContextProvider.notifier)
          .select(
            const SelectedContext(
              countryCode: 'RO',
              stationId: 'batch3-station',
              stationName: 'Baziaș',
              waterId: 'danube-bazias',
              waterName: 'Dunărea',
              riverName: 'Dunărea',
              latitude: 44.8167,
              longitude: 21.3944,
              source: 'AFDJ',
            ),
          );
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('utilities-search-field')),
        'Solunar',
      );
      await tester.pump();
      final weatherUtility = find.byKey(
        const ValueKey('utility-search-weather.solunar'),
      );
      await tester.ensureVisible(weatherUtility);
      await tester.pump();
      await tester.tap(weatherUtility);
      // Selected water/station context is intentionally separate from the
      // physical location used by canonical Weather.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final weatherRoute = find.byKey(
        AppNavigator.destinationKey(AppDestination.weather),
      );
      expect(weatherRoute, findsOneWidget);
      final weatherFinder = find.descendant(
        of: weatherRoute,
        matching: find.byType(WeatherPage),
      );
      expect(weatherFinder, findsOneWidget);
      final weatherPage = tester.widget<WeatherPage>(weatherFinder);
      expect(weatherPage.initialWeather, isNull);
      expect(weatherPage.initialSection, WeatherPageSection.solunar);
    },
  );

  testWidgets(
    'canonical WeatherPage stays flex-safe at 390px and 200 percent text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final snapshot = _snapshot();
      await tester.pumpWidget(
        _app(WeatherPage(initialWeather: snapshot.weather)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(WeatherPage), findsOneWidget);
      expect(find.text('18°'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Water, Weather and Fluvi expose the connected priority actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final snapshot = _snapshot();
      final source = _FakeDataSource(snapshot);

      await tester.pumpWidget(
        _app(
          FigmaWaterHubPage(
            initialStation: snapshot.station,
            dataSource: source,
          ),
        ),
      );
      await _pumpData(tester);
      expect(
        find.byKey(const ValueKey('batch3-water-open-map')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch3-water-open-weather')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch3-water-open-fluvi')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _app(
          FigmaWeatherHubPage(
            initialStation: snapshot.station,
            dataSource: source,
          ),
        ),
      );
      await _pumpData(tester);
      final weatherScrollable = find
          .descendant(
            of: find.byKey(const ValueKey('figma-weather-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('batch3-weather-solunar-section')),
        260,
        scrollable: weatherScrollable,
      );
      expect(
        find.byKey(const ValueKey('batch3-weather-solunar-section')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('batch3-weather-actions')),
        260,
        scrollable: weatherScrollable,
      );
      expect(
        find.byKey(const ValueKey('batch3-weather-open-water')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch3-weather-open-map')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch3-weather-open-fluvi')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _app(
          FigmaFluviHubPage(
            initialStation: snapshot.station,
            dataSource: source,
          ),
        ),
      );
      await _pumpData(tester);
      expect(
        find.byKey(const ValueKey('batch3-fluvi-open-water')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch3-fluvi-open-weather')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('batch3-fluvi-open-map')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Water, Weather and Alerts use the canonical repaired targets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snapshot = _snapshot();
    final source = _FakeDataSource(snapshot);

    await tester.pumpWidget(
      _app(
        FigmaWaterHubPage(initialStation: snapshot.station, dataSource: source),
      ),
    );
    await _pumpData(tester);
    await tester.tap(find.text('Alerte'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(AppNavigator.destinationKey(AppDestination.alerts)),
      findsOneWidget,
    );

    AppNavigator.resetForTesting();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _app(
        FigmaWeatherHubPage(
          initialStation: snapshot.station,
          dataSource: source,
        ),
      ),
    );
    await _pumpData(tester);
    await tester.tap(find.byKey(const ValueKey('weather-open-alerts')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(AppNavigator.destinationKey(AppDestination.newAlert)),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('priority hubs reflow at 200 percent text scaling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final snapshot = _snapshot();
    final source = _FakeDataSource(snapshot);
    final pages = <(Widget, ValueKey<String>)>[
      (
        FigmaWaterHubPage(initialStation: snapshot.station, dataSource: source),
        const ValueKey('figma-water-scroll'),
      ),
      (
        FigmaWeatherHubPage(
          initialStation: snapshot.station,
          dataSource: source,
        ),
        const ValueKey('figma-weather-scroll'),
      ),
      (
        FigmaFluviHubPage(initialStation: snapshot.station, dataSource: source),
        const ValueKey('figma-fluvi-scroll'),
      ),
    ];

    for (final entry in pages) {
      AppNavigator.resetForTesting();
      await tester.pumpWidget(_app(entry.$1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final list = find.byKey(entry.$2);
      expect(list, findsOneWidget);
      await tester.drag(list, const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(list, const Offset(0, -360));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('ro'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark(
      useMaterial3: true,
    ).copyWith(splashFactory: NoSplash.splashFactory),
    home: home,
  ),
);

Future<void> _pumpData(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Station _station() {
  final now = DateTime.now().toUtc();
  return Station(
    id: 'batch3-station',
    name: 'Baziaș',
    river: 'Dunărea',
    level: 690,
    trend: WaterTrend.rising,
    latitude: 44.8167,
    longitude: 21.3944,
    lastUpdate: now.subtract(const Duration(minutes: 18)),
    hasWaterLevel: true,
    hasKnownTrend: true,
    waterLevelSource: 'AFDJ',
  );
}

CommercialHomeSnapshot _snapshot() {
  final now = DateTime.now().toUtc();
  final station = _station();
  final previous = WaterLevel(
    stationId: station.id,
    value: 682,
    timestamp: now.subtract(const Duration(hours: 24)),
    trend: WaterTrend.rising,
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    hasKnownTrend: true,
  );
  final current = WaterLevel(
    stationId: station.id,
    value: 690,
    timestamp: now.subtract(const Duration(minutes: 18)),
    trend: WaterTrend.rising,
    source: WaterLevelSource.afdj,
    sourceName: 'AFDJ',
    hasKnownTrend: true,
  );
  final weatherData = WeatherData(
    temperature: 18,
    feelsLike: 17,
    condition: 'Partly cloudy',
    humidity: 64,
    windSpeed: 12,
    windGusts: 19,
    windDirectionDegrees: 245,
    precipitationProbability: 22,
    cloudCover: 48,
    pressure: 1014,
    observedAt: now,
    forecast: const [],
    hourlyForecast: [
      WeatherForecastHour(
        time: now.add(const Duration(hours: 1)),
        temperature: 18,
        feelsLike: 17,
        humidity: 65,
        precipitationProbability: 20,
        cloudCover: 50,
        windSpeed: 12,
        windGusts: 19,
        windDirectionDegrees: 245,
      ),
    ],
    sunrise: DateTime(now.year, now.month, now.day, 6, 12),
    sunset: DateTime(now.year, now.month, now.day, 20, 24),
    moonPhase: 'Waxing crescent',
    fishingActivity: FishingActivity.good,
  );
  return CommercialHomeSnapshot(
    station: station,
    water: WaterUiResult(
      latestReading: current,
      previousReading: previous,
      history: [previous, current],
      source: WaterLevelSource.afdj,
      sourceName: 'AFDJ',
      measurementTimestamp: current.timestamp,
      dataAge: const Duration(minutes: 18),
      isStale: false,
      status: WaterUiStatus.availableHistory,
      safeDiagnosticMessage: null,
      deltaCm: 8,
      comparisonDuration: const Duration(hours: 24),
      trend: WaterTrend.rising,
      hasEnoughHistory: true,
    ),
    weather: WeatherHomeResult(
      data: weatherData,
      latitude: station.latitude,
      longitude: station.longitude,
      locationSource: WeatherLocationSource.stationFallback,
      status: WeatherHomeStatus.available,
      dataTimestamp: now,
      dataAge: Duration.zero,
      isStale: false,
      safeDiagnosticMessage: null,
    ),
    score: const FishingScoreResult(
      score: 78,
      rating: FishingScoreRating.good,
      recommendation: 'Condiții bune',
      explanation: 'Apa, vremea și lumina susțin această fereastră.',
      positiveFactors: ['Water history supports the trend'],
      negativeFactors: ['Strong wind gusts'],
      missingFactors: [],
      bestTime: '18:30–20:30',
      confidence: 75,
      moonPhase: 'Waxing crescent',
      goldenHour: '18:30–20:30',
    ),
    communityPosts: const <CommunityPost>[],
    loadedAt: now,
  );
}

class _FakeDataSource implements CommercialHomeDataSource {
  const _FakeDataSource(this.snapshot);

  final CommercialHomeSnapshot snapshot;

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      snapshot;
}
