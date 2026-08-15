import 'dart:async';

import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/map/pending_map_camera.dart';
import 'package:fishtrack/core/runtime/app_runtime.dart';
import 'package:fishtrack/features/commercial_home/data/commercial_home_data_source.dart';
import 'package:fishtrack/l10n/app_localizations.dart';
import 'package:fishtrack/main.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/screens/main_navigation.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'app-runtime-test-key',
    );
  });

  testWidgets(
    'authenticated MainNavigation initiates runtime automatically once',
    (tester) async {
      final source = _ProgressiveRuntimeLocationSource(
        current: _location(latitude: 51.4545, longitude: -2.5879),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: MainNavigation(
              homeDataSource: const _RuntimeHomeDataSource(),
              homeMapOverride: const ColoredBox(color: Colors.black),
              mapPageOverride: const SizedBox.shrink(),
              communityPageOverride: const SizedBox.shrink(),
              favoritesPageOverride: const SizedBox.shrink(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final context = tester.element(find.byType(MainNavigation));
      final container = ProviderScope.containerOf(context, listen: false);
      expect(
        identical(container.read(deviceLocationSourceProvider), source),
        isTrue,
      );
      final runtime = container.read(appRuntimeProvider);
      expect(runtime.status, isNot(AppRuntimeStatus.idle));
      expect(runtime.attempts, 1);
    },
  );

  test('concurrent runtime consumers share one initial GPS request', () async {
    final current = Completer<CurrentDeviceLocation>();
    final source = _ProgressiveRuntimeLocationSource(
      currentFuture: current.future,
    );
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final first = container
        .read(appRuntimeProvider.notifier)
        .start(languageCode: 'en');
    final second = container
        .read(appRuntimeProvider.notifier)
        .start(languageCode: 'en');

    expect(identical(first, second), isTrue);
    await source.currentRequested.future;
    expect(source.currentRequests, 1);
    current.complete(_location(latitude: 51.4545, longitude: -2.5879));
    await Future.wait([first, second]);
    expect(source.currentRequests, 1);
  });

  test('runtime cached-to-available lifecycle ends with current GPS', () async {
    final current = Completer<CurrentDeviceLocation>();
    final source = _ProgressiveRuntimeLocationSource(
      lastKnown: _location(latitude: 51.4500, longitude: -2.5800),
      currentFuture: current.future,
    );
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final startup = container
        .read(appRuntimeProvider.notifier)
        .start(languageCode: 'en');
    await source.currentRequested.future;
    expect(
      container.read(currentLocationProvider).status,
      CurrentLocationStatus.cached,
    );

    current.complete(_location(latitude: 51.4545, longitude: -2.5879));
    final runtime = await startup;

    expect(runtime.status, AppRuntimeStatus.ready);
    expect(runtime.locationStatus, CurrentLocationStatus.available);
    expect(container.read(currentLocationProvider).location?.latitude, 51.4545);
  });

  test('reverse geocoding enriches the same physical location state', () async {
    final locality = Completer<DeviceLocality?>();
    final source = _ProgressiveRuntimeLocationSource(
      current: _location(latitude: 51.4545, longitude: -2.5879),
      localityFuture: locality.future,
    );
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    await container.read(appRuntimeProvider.notifier).start(languageCode: 'en');
    final coordinates = container.read(currentLocationProvider).location;
    expect(coordinates?.label, isNull);

    locality.complete(
      const DeviceLocality(
        label: 'Patchway, South Gloucestershire',
        locality: 'Patchway',
        region: 'South Gloucestershire',
        countryCode: 'GB',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final enriched = container.read(currentLocationProvider).location;
    expect(identical(enriched, coordinates), isFalse);
    expect(enriched?.latitude, coordinates?.latitude);
    expect(enriched?.longitude, coordinates?.longitude);
    expect(enriched?.label, 'Patchway, South Gloucestershire');
    expect(container.read(contentRegionProvider)?.countryCode, 'GB');
  });

  test('selected and map contexts cannot mutate physical location', () async {
    final source = _ProgressiveRuntimeLocationSource(
      current: _location(latitude: 51.4545, longitude: -2.5879),
    );
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    await container.read(appRuntimeProvider.notifier).start(languageCode: 'en');
    final physicalBefore = container.read(currentLocationProvider);

    container.read(selectedContextProvider.notifier).selectStation(_station());
    final camera = PendingMapCameraCoordinator()
      ..request(
        const RuntimeMapCameraTarget(
          source: 'search',
          entityId: 'bucharest',
          latitude: 44.4268,
          longitude: 26.1025,
          zoom: 13.5,
        ),
      );

    expect(camera.activeTarget?.entityId, 'bucharest');
    expect(container.read(selectedContextProvider)?.stationId, 'bazias');
    expect(
      identical(container.read(currentLocationProvider), physicalBefore),
      isTrue,
    );
  });

  test('fresh available physical location is reused on resume', () async {
    final source = _ProgressiveRuntimeLocationSource(
      current: _location(latitude: 51.4545, longitude: -2.5879),
    );
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    await container.read(appRuntimeProvider.notifier).start(languageCode: 'en');
    await container
        .read(appRuntimeProvider.notifier)
        .refreshIfStale(languageCode: 'en');

    expect(source.currentRequests, 1);
    expect(container.read(appRuntimeProvider).attempts, 1);
  });

  testWidgets('failed dependency shows a recoverable startup surface', (
    tester,
  ) async {
    var attempts = 0;
    Future<ApplicationControllers> fail() async {
      attempts++;
      throw StateError('dependency unavailable');
    }

    await tester.pumpWidget(AppBootstrap(initialize: fail));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('startup-retry')), findsOneWidget);
    expect(find.text('FluviAI could not start'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.byKey(const ValueKey('startup-retry')));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.byKey(const ValueKey('startup-retry')), findsOneWidget);
  });
}

CurrentDeviceLocation _location({
  required double latitude,
  required double longitude,
}) => CurrentDeviceLocation(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: 8,
  observedAt: DateTime.now(),
);

Station _station() => Station(
  id: 'bazias',
  name: 'Bazias',
  river: 'Danube',
  level: 100,
  trend: WaterTrend.stable,
  latitude: 44.8167,
  longitude: 21.3944,
  lastUpdate: DateTime.now(),
);

class _ProgressiveRuntimeLocationSource
    implements DeviceLocationSource, ProgressiveDeviceLocationSource {
  _ProgressiveRuntimeLocationSource({
    this.lastKnown,
    CurrentDeviceLocation? current,
    Future<CurrentDeviceLocation>? currentFuture,
    Future<DeviceLocality?>? localityFuture,
  }) : _currentFuture =
           currentFuture ?? SynchronousFuture<CurrentDeviceLocation?>(current),
       _localityFuture =
           localityFuture ?? SynchronousFuture<DeviceLocality?>(null);

  final CurrentDeviceLocation? lastKnown;
  final Future<CurrentDeviceLocation?> _currentFuture;
  final Future<DeviceLocality?> _localityFuture;
  final Completer<void> currentRequested = Completer<void>();
  int currentRequests = 0;

  @override
  Future<CurrentDeviceLocation?> getLastKnownCoordinates() =>
      SynchronousFuture<CurrentDeviceLocation?>(lastKnown);

  @override
  Future<CurrentDeviceLocation> getCurrentCoordinates() async {
    currentRequests++;
    if (!currentRequested.isCompleted) currentRequested.complete();
    final current = await _currentFuture;
    if (current == null) {
      throw const LocationFailure(LocationFailureReason.unavailable);
    }
    return current;
  }

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) => getCurrentCoordinates();

  @override
  Future<DeviceLocality?> resolveDeviceLocality(
    CurrentDeviceLocation location, {
    required String languageCode,
  }) => _localityFuture;
}

class _RuntimeHomeDataSource implements CommercialHomeDataSource {
  const _RuntimeHomeDataSource();

  @override
  Stream<Station> get stationSelections => const Stream<Station>.empty();

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async =>
      CommercialHomeSnapshot(
        station: null,
        water: null,
        weather: null,
        score: null,
        communityPosts: const [],
        loadedAt: DateTime.now(),
      );
}
