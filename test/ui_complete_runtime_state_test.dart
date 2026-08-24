import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/runtime/app_runtime.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/services/fishing_score_service.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('runtime hubs expose a truthful error and retry state', (
    tester,
  ) async {
    final source = _RetryableFailingDataSource();
    await tester.pumpWidget(_app(FigmaWaterHubPage(dataSource: source)));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('figma-runtime-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('figma-runtime-retry')), findsOneWidget);
    expect(find.text('Datele nu au putut fi încărcate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('figma-runtime-retry')));
    await tester.pump();
    await tester.pump();
    expect(source.attempts, 2);
    expect(find.byKey(const ValueKey('figma-runtime-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime error state reflows at 200 percent text scaling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      _app(FigmaWeatherHubPage(dataSource: _RetryableFailingDataSource())),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('figma-runtime-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Water Hub one official observation keeps canonical unknown presentation',
    (tester) async {
      final now = DateTime.now().toUtc();
      final reading = WaterLevel(
        stationId: 'bechet',
        value: -105,
        timestamp: now.subtract(const Duration(hours: 1)),
        trend: WaterTrend.stable,
        source: WaterLevelSource.afdj,
        sourceName: 'AFDJ',
        hasKnownTrend: false,
      );
      final station = Station(
        id: 'bechet',
        name: 'Bechet',
        river: 'Dunarea',
        level: reading.value,
        trend: WaterTrend.stable,
        latitude: 43.78,
        longitude: 23.95,
        lastUpdate: reading.timestamp,
        hasWaterLevel: true,
        hasKnownTrend: false,
        waterLevelSource: 'AFDJ',
      );
      final water = WaterUiResult(
        latestReading: reading,
        history: [reading],
        source: WaterLevelSource.afdj,
        sourceName: 'AFDJ',
        measurementTimestamp: reading.timestamp,
        dataAge: const Duration(hours: 1),
        isStale: false,
        status: WaterUiStatus.insufficientHistory,
        safeDiagnosticMessage: null,
      );
      final canonical = resolveWaterOfficialObservationState(water);

      expect(canonical.currentReading?.value, -105);
      expect(canonical.deltaCm, isNull);
      expect(canonical.trend, isNull);

      await tester.pumpWidget(
        _app(
          FigmaWaterHubPage(
            initialStation: station,
            dataSource: _StaticWaterDataSource(
              CommercialHomeSnapshot(
                station: station,
                water: water,
                weather: null,
                score: null,
                communityPosts: const [],
                loadedAt: now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('-105'), findsWidgets);
      expect(find.text('Trend indisponibil'), findsOneWidget);
      expect(find.textContaining('/ 24h'), findsNothing);
      expect(find.text('Stabil'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'runtime snapshot builder gives explicit station context precedence',
    (tester) async {
      final station = Station(
        id: 'station-b',
        name: 'Station B',
        river: 'Dunărea',
        countryCode: 'RO',
        level: 100,
        trend: WaterTrend.stable,
        latitude: 45,
        longitude: 23,
        lastUpdate: DateTime.now(),
        hasWaterLevel: true,
      );
      final source = _ContextRecordingDataSource();

      await tester.pumpWidget(
        _app(FigmaFluviHubPage(initialStation: station, dataSource: source)),
      );
      await tester.pumpAndSettle();

      expect(source.genericLoads, 0);
      expect(source.contexts.single.stationId, 'station-b');
      expect(source.contexts.single.primaryLabel, 'Station B');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home and Fluvi Hub share fresh physical score availability', (
    tester,
  ) async {
    final physical = CurrentDeviceLocation(
      latitude: 51.4545,
      longitude: -2.5879,
      accuracyMeters: 8,
      observedAt: DateTime.now(),
      label: 'Patchway',
      countryCode: 'GB',
    );
    final locationSource = _RecordingLocationSource(physical);
    final dataSource = _PhysicalScoreDataSource();
    final container = ProviderContainer(
      overrides: [
        deviceLocationSourceProvider.overrideWithValue(locationSource),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _appWithContainer(
        CommercialHomePage(
          onNavigate: (_) {},
          dataSource: dataSource,
          mapOverride: const SizedBox.shrink(),
        ),
        container,
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _appWithContainer(FigmaFluviHubPage(dataSource: dataSource), container),
    );
    await tester.pumpAndSettle();

    expect(locationSource.currentRequests, 1);
    expect(dataSource.genericLoads, 0);
    expect(dataSource.contextLoads, 0);
    expect(dataSource.physicalLocations, hasLength(2));
    expect(
      dataSource.physicalLocations
          .map((location) => (location.latitude, location.longitude))
          .toSet(),
      {(51.4545, -2.5879)},
    );
    expect(
      dataSource.returnedScores.every((score) => score.hasEnoughData),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed stale Hub refresh stays notEnough without SelectedContext fallback',
    (tester) async {
      final locationSource = _FailingRefreshLocationSource(
        CurrentDeviceLocation(
          latitude: 51.4545,
          longitude: -2.5879,
          accuracyMeters: 8,
          observedAt: DateTime.now().subtract(const Duration(minutes: 6)),
          label: 'Patchway',
          countryCode: 'GB',
        ),
      );
      final dataSource = _PhysicalScoreDataSource();
      final container = ProviderContainer(
        overrides: [
          deviceLocationSourceProvider.overrideWithValue(locationSource),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(appRuntimeProvider.notifier)
          .start(languageCode: 'en');
      container
          .read(selectedContextProvider.notifier)
          .selectStation(_selectedStation());

      await tester.pumpWidget(
        _appWithContainer(FigmaFluviHubPage(dataSource: dataSource), container),
      );
      for (
        var attempt = 0;
        attempt < 20 && locationSource.currentRequests < 2;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FigmaFluviHubPage), findsOneWidget);
      expect(
        (
          locationSource.currentRequests,
          dataSource.genericLoads,
          dataSource.physicalLocations.length,
          dataSource.contextLoads,
          dataSource.returnedScores.length,
        ),
        (2, 1, 0, 0, 1),
      );
      expect(dataSource.returnedScores.single.hasEnoughData, isFalse);
      expect(
        container.read(selectedContextProvider)?.stationId,
        'selected-station',
      );
      expect(
        container.read(currentLocationProvider).hasUsableLocation,
        isFalse,
      );
      expect(
        container.read(appRuntimeProvider).status,
        AppRuntimeStatus.degraded,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(Widget home) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('ro'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark(useMaterial3: true),
    home: home,
  ),
);

Widget _appWithContainer(Widget home, ProviderContainer container) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: home,
      ),
    );

class _RetryableFailingDataSource implements CommercialHomeDataSource {
  var attempts = 0;

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) {
    attempts++;
    return Future<CommercialHomeSnapshot>.error(
      StateError('offline-test-$attempts'),
    );
  }
}

class _StaticWaterDataSource implements CommercialHomeDataSource {
  const _StaticWaterDataSource(this.snapshot);

  final CommercialHomeSnapshot snapshot;

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      snapshot;
}

class _ContextRecordingDataSource
    implements CommercialHomeDataSource, ContextAwareCommercialHomeDataSource {
  final contexts = <FluviResolvedContext>[];
  var genericLoads = 0;

  @override
  Stream<Station> get stationSelections => const Stream.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async {
    genericLoads++;
    throw StateError('Generic load must not replace explicit context.');
  }

  @override
  Future<CommercialHomeSnapshot> loadForContext(
    FluviResolvedContext context, {
    bool forceRefresh = false,
  }) async {
    contexts.add(context);
    return CommercialHomeSnapshot(
      station: null,
      water: null,
      weather: null,
      score: null,
      communityPosts: const [],
      loadedAt: DateTime.now(),
      resolvedContext: context,
      waterStatus: CommercialHomeDomainStatus.unavailable,
      weatherStatus: CommercialHomeDomainStatus.unavailable,
      scoreStatus: CommercialHomeDomainStatus.unavailable,
      communityStatus: CommercialHomeDomainStatus.unavailable,
    );
  }
}

class _RecordingLocationSource implements DeviceLocationSource {
  _RecordingLocationSource(this.location);

  final CurrentDeviceLocation location;
  int currentRequests = 0;

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) async {
    currentRequests++;
    return location;
  }
}

class _FailingRefreshLocationSource implements DeviceLocationSource {
  _FailingRefreshLocationSource(this.initialLocation);

  final CurrentDeviceLocation initialLocation;
  int currentRequests = 0;

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) async {
    currentRequests++;
    if (currentRequests == 1) return initialLocation;
    throw const LocationFailure(LocationFailureReason.unavailable);
  }
}

class _PhysicalScoreDataSource
    implements
        CommercialHomeDataSource,
        CurrentLocationAwareCommercialHomeDataSource,
        ContextAwareCommercialHomeDataSource {
  final physicalLocations = <CurrentDeviceLocation>[];
  final returnedScores = <FishingScoreResult>[];
  var genericLoads = 0;
  var contextLoads = 0;

  @override
  Stream<Station> get stationSelections => const Stream.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async {
    genericLoads++;
    const score = FishingScoreResult.notEnough();
    returnedScores.add(score);
    return _snapshot(score: score);
  }

  @override
  Future<CommercialHomeSnapshot> loadForCurrentLocation(
    CurrentDeviceLocation location, {
    bool forceRefresh = false,
  }) async {
    physicalLocations.add(location);
    returnedScores.add(_availableScore);
    return _snapshot(score: _availableScore, location: location);
  }

  @override
  Future<CommercialHomeSnapshot> loadForContext(
    FluviResolvedContext context, {
    bool forceRefresh = false,
  }) async {
    contextLoads++;
    returnedScores.add(_availableScore);
    return _snapshot(score: _availableScore, resolvedContext: context);
  }
}

const _availableScore = FishingScoreResult(
  score: 72.5,
  rating: FishingScoreRating.good,
  recommendation: 'Good',
  explanation: 'Canonical physical fixture',
  positiveFactors: ['Real weather'],
  negativeFactors: [],
  missingFactors: [],
  bestTime: 'Morning',
  confidence: 75,
  moonPhase: 'Waxing',
  goldenHour: '06:00',
);

CommercialHomeSnapshot _snapshot({
  required FishingScoreResult score,
  CurrentDeviceLocation? location,
  FluviResolvedContext? resolvedContext,
}) => CommercialHomeSnapshot(
  station: null,
  water: null,
  weather: null,
  score: score,
  communityPosts: const [],
  loadedAt: DateTime.now(),
  currentLocation: location,
  resolvedContext:
      resolvedContext ??
      resolveFluviContext(selected: null, physicalLocation: location),
  waterStatus: CommercialHomeDomainStatus.unavailable,
  weatherStatus: CommercialHomeDomainStatus.unavailable,
  scoreStatus: score.hasEnoughData
      ? CommercialHomeDomainStatus.available
      : CommercialHomeDomainStatus.unavailable,
  communityStatus: CommercialHomeDomainStatus.unavailable,
);

Station _selectedStation() => Station(
  id: 'selected-station',
  name: 'Selected station',
  river: 'Danube',
  level: 100,
  trend: WaterTrend.stable,
  latitude: 44.8,
  longitude: 21.4,
  lastUpdate: DateTime.now(),
  hasWaterLevel: true,
);
