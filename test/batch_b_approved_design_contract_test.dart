import 'dart:io';

import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/services/weather_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Water uses the approved review hierarchy with real snapshot data',
    (tester) async {
      _configurePhone(tester);

      const source = _BatchBDataSource();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ro'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: ThemeData.dark(
              useMaterial3: true,
            ).copyWith(splashFactory: NoSplash.splashFactory),
            home: FigmaWaterHubPage(
              initialStation: _station,
              dataSource: source,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inteligență Hidrologică'), findsOneWidget);
      expect(find.text('Tendință nivel · 7 zile'), findsOneWidget);
      expect(
        find.text('Perioadele fără date nu sunt estimate.'),
        findsOneWidget,
      );
      expect(find.text('Deschide Pulsul Râului'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('batch-b-water-official-chart')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Weather uses approved current/hourly/decision sections', (
    tester,
  ) async {
    _configurePhone(tester);

    const source = _BatchBDataSource();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(
            useMaterial3: true,
          ).copyWith(splashFactory: NoSplash.splashFactory),
          home: FigmaWeatherHubPage(
            initialStation: _station,
            dataSource: source,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vreme & Solunar'), findsOneWidget);
    expect(find.text('CONDIȚII ACTUALE'), findsOneWidget);
    expect(find.text('URMĂTOARELE 12 ORE'), findsOneWidget);
    expect(find.text('DECIZIE PESCUIT'), findsOneWidget);
    expect(find.text('Prognoză extinsă'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'FluviScore uses approved explainable hierarchy without fake points',
    (tester) async {
      _configurePhone(tester);

      const source = _BatchBDataSource();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ro'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: ThemeData.dark(
              useMaterial3: true,
            ).copyWith(splashFactory: NoSplash.splashFactory),
            home: FigmaFluviHubPage(
              initialStation: _station,
              dataSource: source,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FluviScore'), findsOneWidget);
      expect(find.text('EXPLICABIL'), findsOneWidget);
      expect(find.text('DE CE ACEST SCOR'), findsOneWidget);
      expect(find.text('Proveniența scorului'), findsOneWidget);
      expect(find.textContaining('+12'), findsNothing);
      expect(find.textContaining('−9'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Full Map source contains approved review controls and no second nav',
    () {
      final source = File('lib/screens/map_page.dart').readAsStringSync();
      expect(source, contains("ValueKey('figma-full-map-search')"));
      expect(source, contains("ValueKey('figma-full-map-layers')"));
      expect(source, contains("ValueKey('figma-full-map-boat-hud')"));
      expect(source, contains("ValueKey('figma-full-map-locate')"));
      expect(source, contains("ValueKey('figma-full-map-quick-report')"));
      expect(source, contains('Întreabă Fluvi'));
      expect(source, isNot(contains('bottomNavigationBar:')));
    },
  );
}

void _configurePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _station = Station(
  id: 'batch-b-station',
  name: 'Bristol',
  river: 'River Avon',
  level: 214,
  trend: WaterTrend.falling,
  latitude: 51.4545,
  longitude: -2.5879,
  lastUpdate: _now,
  hasWaterLevel: true,
  hasKnownTrend: true,
  waterLevelSource: 'EA',
);

final _now = DateTime(2026, 8, 8, 12);

class _BatchBDataSource implements CommercialHomeDataSource {
  const _BatchBDataSource();

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async {
    final history = <WaterLevel>[
      WaterLevel(
        stationId: _station.id,
        value: 225,
        timestamp: _now.subtract(const Duration(hours: 48)),
        trend: WaterTrend.falling,
        source: WaterLevelSource.afdj,
        sourceName: 'EA',
        hasKnownTrend: true,
      ),
      WaterLevel(
        stationId: _station.id,
        value: 220,
        timestamp: _now.subtract(const Duration(hours: 24)),
        trend: WaterTrend.falling,
        source: WaterLevelSource.afdj,
        sourceName: 'EA',
        hasKnownTrend: true,
      ),
      WaterLevel(
        stationId: _station.id,
        value: 214,
        timestamp: _now,
        trend: WaterTrend.falling,
        source: WaterLevelSource.afdj,
        sourceName: 'EA',
        hasKnownTrend: true,
      ),
    ];
    final weatherData = WeatherData(
      temperature: 18,
      condition: 'Parțial noros',
      humidity: 72,
      windSpeed: 14,
      windGusts: 24,
      windDirectionDegrees: 225,
      precipitationProbability: 20,
      cloudCover: 55,
      pressure: 1016,
      observedAt: _now,
      forecast: [
        WeatherForecastDay(
          date: _now,
          minimumTemperature: 12,
          maximumTemperature: 20,
          condition: 'Parțial noros',
          sunrise: DateTime(2026, 8, 8, 5, 40),
          sunset: DateTime(2026, 8, 8, 20, 45),
        ),
      ],
      hourlyForecast: List<WeatherForecastHour>.generate(
        4,
        (index) => WeatherForecastHour(
          time: _now.add(Duration(hours: index * 3)),
          temperature: 18.0 - index,
          feelsLike: 18.0 - index,
          humidity: 70,
          precipitationProbability: 20,
          cloudCover: 50,
          windSpeed: 14.0 + index,
          windGusts: 20.0 + index,
          windDirectionDegrees: 225,
        ),
      ),
      moonPhase: 'First quarter',
      fishingActivity: FishingActivity.good,
    );
    return CommercialHomeSnapshot(
      station: _station,
      water: WaterUiResult(
        latestReading: history.last,
        previousReading: history[1],
        history: history,
        source: WaterLevelSource.afdj,
        sourceName: 'EA',
        measurementTimestamp: _now,
        dataAge: const Duration(minutes: 18),
        isStale: false,
        status: WaterUiStatus.availableHistory,
        safeDiagnosticMessage: null,
        deltaCm: -6,
        comparisonDuration: const Duration(hours: 24),
        trend: WaterTrend.falling,
        hasEnoughHistory: true,
      ),
      weather: WeatherHomeResult(
        data: weatherData,
        latitude: _station.latitude,
        longitude: _station.longitude,
        locationSource: WeatherLocationSource.stationFallback,
        status: WeatherHomeStatus.available,
        dataTimestamp: _now,
        dataAge: const Duration(minutes: 18),
        isStale: false,
        safeDiagnosticMessage: null,
      ),
      score: const FishingScoreResult(
        score: 76,
        rating: FishingScoreRating.good,
        recommendation: 'Condiții bune acum',
        explanation: 'Semnalele disponibile sunt favorabile.',
        positiveFactors: ['Schimbarea apei este treptată', 'Presiune stabilă'],
        negativeFactors: ['Risc de vânt după 15:00'],
        missingFactors: ['Dovezi de capturi limitate'],
        bestTime: '05:40–08:20',
        confidence: 64,
        moonPhase: 'First quarter',
        goldenHour: '05:40–06:40',
      ),
      communityPosts: const <CommunityPost>[],
      loadedAt: _now,
    );
  }
}
