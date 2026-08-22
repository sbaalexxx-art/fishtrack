import 'dart:async';

import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/models/station.dart';
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

  testWidgets(
    'explicit Frunzaru context is retained by Ask without Danube fallback',
    (tester) async {
      final context = resolveFluviContext(
        selected: const SelectedContext(
          countryCode: 'RO',
          locationName: 'Frunzaru',
          latitude: 44.333,
          longitude: 24.617,
          hydropowerPlantId: 'frunzaru',
          source: 'Hydro entity',
        ),
        physicalLocation: null,
      )!;
      final source = _RecordingContextSource();

      await tester.pumpWidget(
        _app(FigmaAskFluviPage(dataSource: source, initialContext: context)),
      );
      await tester.enterText(find.byType(TextField), 'Cum este apa aici?');
      await tester.tap(find.textContaining('Trimite'));
      await tester.pumpAndSettle();

      expect(source.contexts.single.contextKey, context.contextKey);
      expect(source.contexts.single.primaryLabel, 'Frunzaru');
      expect(find.textContaining('Frunzaru'), findsWidgets);
      expect(find.textContaining('Bazia'), findsNothing);
      expect(find.textContaining('Moldova Veche'), findsNothing);
    },
  );

  testWidgets('direct Ask uses current GPS when there is no explicit context', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        deviceLocationSourceProvider.overrideWithValue(
          _StaticLocationSource(
            CurrentDeviceLocation(
              latitude: 51.4545,
              longitude: -2.5879,
              accuracyMeters: 8,
              observedAt: DateTime.now(),
              label: 'Bristol',
              countryCode: 'GB',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(currentLocationProvider.notifier)
        .refresh(languageCode: 'en');
    final source = _RecordingContextSource();

    await tester.pumpWidget(
      _app(FigmaAskFluviPage(dataSource: source), container: container),
    );
    await tester.enterText(find.byType(TextField), 'Cum este apa aici?');
    await tester.tap(find.textContaining('Trimite'));
    await tester.pumpAndSettle();

    expect(
      source.contexts.single.source,
      FluviResolvedContextSource.physicalGps,
    );
    expect(source.contexts.single.primaryLabel, 'Bristol');
    expect(find.textContaining('Bristol'), findsWidgets);
  });

  test('Map station B wins over persistent Water station A', () {
    final water = WaterService();
    final stationA = _station('station-a', 'Danube A', 44.0, 22.0);
    final stationB = _station('station-b', 'Danube B', 45.0, 23.0);
    water.selectStation(stationA);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(selectedContextProvider.notifier).publishStation(stationB);
    final resolved = container.read(canonicalFluviContextProvider);

    expect(water.selectedStation?.id, 'station-a');
    expect(resolved?.stationId, 'station-b');
    expect(resolved?.primaryLabel, 'Danube B');
  });

  test('Water and Favorite contexts retain the same explicit identity', () {
    final station = _station('frunzaru-station', 'Frunzaru', 44.333, 24.617);
    final waterContext = resolveFluviContext(
      selected: SelectedContext.fromStation(station),
      physicalLocation: null,
    )!;
    final favoriteContext = resolveFluviContext(
      selected: SelectedContext.fromStation(
        station,
      ).copyWith(origin: SelectedContextOrigin.favorite),
      physicalLocation: null,
    )!;

    expect(waterContext.stationId, station.id);
    expect(waterContext.primaryLabel, station.name);
    expect(favoriteContext.stationId, station.id);
    expect(favoriteContext.primaryLabel, station.name);
    expect(favoriteContext.source, FluviResolvedContextSource.favorite);
    expect(favoriteContext.contextKey, isNot(waterContext.contextKey));
  });

  testWidgets(
    'stale Ask completion is ignored after canonical context changes',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(selectedContextProvider.notifier)
          .publishStation(_station('station-a', 'Station A', 44.0, 22.0));
      final source = _DeferredContextSource();

      await tester.pumpWidget(
        _app(FigmaAskFluviPage(dataSource: source), container: container),
      );
      await tester.enterText(find.byType(TextField), 'Cum este apa aici?');
      await tester.tap(find.textContaining('Trimite'));
      await tester.pump();
      expect(source.requests.single.primaryLabel, 'Station A');

      container
          .read(selectedContextProvider.notifier)
          .publishStation(_station('station-b', 'Station B', 45.0, 23.0));
      await tester.pump();
      source.completers.single.complete(_emptySnapshot(source.requests.single));
      await tester.pumpAndSettle();

      expect(find.textContaining('Station B'), findsWidgets);
      expect(find.textContaining('Pentru Station A'), findsNothing);
    },
  );
}

Widget _app(Widget home, {ProviderContainer? container}) {
  final app = MaterialApp(
    locale: const Locale('ro'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData.dark(useMaterial3: true),
    home: home,
  );
  return container == null
      ? ProviderScope(child: app)
      : UncontrolledProviderScope(container: container, child: app);
}

CommercialHomeSnapshot _emptySnapshot(FluviResolvedContext context) =>
    CommercialHomeSnapshot(
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

class _RecordingContextSource
    implements CommercialHomeDataSource, ContextAwareCommercialHomeDataSource {
  final contexts = <FluviResolvedContext>[];

  @override
  Stream<Station> get stationSelections => const Stream.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      throw StateError('Generic load must not replace canonical context.');

  @override
  Future<CommercialHomeSnapshot> loadForContext(
    FluviResolvedContext context, {
    bool forceRefresh = false,
  }) async {
    contexts.add(context);
    return _emptySnapshot(context);
  }
}

class _DeferredContextSource
    implements CommercialHomeDataSource, ContextAwareCommercialHomeDataSource {
  final requests = <FluviResolvedContext>[];
  final completers = <Completer<CommercialHomeSnapshot>>[];

  @override
  Stream<Station> get stationSelections => const Stream.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      throw StateError('Generic load must not replace canonical context.');

  @override
  Future<CommercialHomeSnapshot> loadForContext(
    FluviResolvedContext context, {
    bool forceRefresh = false,
  }) {
    requests.add(context);
    final completer = Completer<CommercialHomeSnapshot>();
    completers.add(completer);
    return completer.future;
  }
}

class _StaticLocationSource implements DeviceLocationSource {
  const _StaticLocationSource(this.location);

  final CurrentDeviceLocation location;

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) async => location;
}

Station _station(String id, String name, double latitude, double longitude) =>
    Station(
      id: id,
      name: name,
      river: 'Dunărea',
      countryCode: 'RO',
      level: 100,
      trend: WaterTrend.stable,
      latitude: latitude,
      longitude: longitude,
      lastUpdate: DateTime.now(),
      hasWaterLevel: true,
    );
