import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/core/map/map_feature_registry.dart';
import 'package:fishtrack/core/map/pending_map_camera.dart';
import 'package:fishtrack/screens/map_page.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const firstTarget = RuntimeMapCameraTarget(
    source: 'runtime-test',
    entityId: 'station-a',
    latitude: 45.1,
    longitude: 24.2,
    zoom: 13.5,
  );
  const secondTarget = RuntimeMapCameraTarget(
    source: 'runtime-test',
    entityId: 'station-b',
    latitude: 46.2,
    longitude: 25.3,
    zoom: 13.5,
  );

  test('camera context waits for map creation and initial style', () {
    final coordinator = PendingMapCameraCoordinator();
    final requestId = coordinator.request(firstTarget);

    expect(coordinator.takeReadyApplication(), isNull);
    coordinator.markMapCreated();
    expect(coordinator.takeReadyApplication(), isNull);
    coordinator.markStyleLoaded();

    final application = coordinator.takeReadyApplication();
    expect(application?.requestId, requestId);
    expect(application?.target.entityId, firstTarget.entityId);
    expect(application?.isReplay, isFalse);
    expect(coordinator.takeReadyApplication(), isNull);
  });

  test('camera context arriving after map and style applies once', () {
    final coordinator = PendingMapCameraCoordinator()
      ..markMapCreated()
      ..markStyleLoaded();

    coordinator.request(firstTarget);
    expect(
      coordinator.takeReadyApplication()?.target.entityId,
      firstTarget.entityId,
    );
    expect(coordinator.takeReadyApplication(), isNull);
  });

  test('style reload replays the active runtime target', () {
    final coordinator = PendingMapCameraCoordinator()
      ..markMapCreated()
      ..markStyleLoaded()
      ..request(firstTarget);
    final first = coordinator.takeReadyApplication();

    coordinator.markStyleLoading();
    expect(coordinator.takeReadyApplication(), isNull);
    coordinator.markStyleLoaded();
    final replay = coordinator.takeReadyApplication();

    expect(replay?.requestId, first?.requestId);
    expect(replay?.target.entityId, firstTarget.entityId);
    expect(replay?.isReplay, isTrue);
    expect(coordinator.takeReadyApplication(), isNull);
  });

  test('leaving and re-entering Full Map retains runtime target', () {
    final coordinator = PendingMapCameraCoordinator()
      ..markMapCreated()
      ..markStyleLoaded()
      ..request(firstTarget);
    coordinator.takeReadyApplication();

    coordinator.markReentered();
    final replay = coordinator.takeReadyApplication();

    expect(replay?.target.entityId, firstTarget.entityId);
    expect(replay?.isReplay, isTrue);
  });

  test('two consecutive stations replace the runtime camera target', () {
    final coordinator = PendingMapCameraCoordinator()
      ..markMapCreated()
      ..markStyleLoaded();

    final firstRequest = coordinator.request(firstTarget);
    final first = coordinator.takeReadyApplication();
    final secondRequest = coordinator.request(secondTarget);
    final second = coordinator.takeReadyApplication();

    expect(first?.requestId, firstRequest);
    expect(first?.target.entityId, firstTarget.entityId);
    expect(second?.requestId, secondRequest);
    expect(secondRequest, greaterThan(firstRequest));
    expect(second?.target.entityId, secondTarget.entityId);
    expect(coordinator.takeReadyApplication(), isNull);
  });

  test('invalid or placeholder coordinates cannot become camera targets', () {
    expect(
      isValidRuntimeMapCoordinate(firstTarget.latitude, firstTarget.longitude),
      isTrue,
    );
    expect(isValidRuntimeMapCoordinate(0, 0), isFalse);
    expect(isValidRuntimeMapCoordinate(double.nan, 25), isFalse);
    expect(isValidRuntimeMapCoordinate(91, 25), isFalse);
  });

  test(
    'Map focus requests are consumed exactly once, including repeat station',
    () {
      final controller = MapFocusController();
      addTearDown(controller.dispose);
      final station = _station(
        id: 'bazias',
        name: 'Baziaș',
        latitude: 44.8167,
        longitude: 21.3944,
      );

      controller.requestStation(station);
      final first = controller.takePending();
      expect(first, isNotNull);
      expect(first!.station!.id, 'bazias');
      expect(controller.takePending(), isNull);

      controller.requestStation(station);
      final second = controller.takePending();
      expect(second, isNotNull);
      expect(second!.id, greaterThan(first.id));
      expect(second.station!.id, first.station!.id);
      expect(controller.takePending(), isNull);
    },
  );

  test('station eligibility is independent from local radius', () {
    final bazias = _station(
      id: 'bazias',
      name: 'Baziaș',
      latitude: 44.8167,
      longitude: 21.3944,
    );
    final bristol = _station(
      id: 'bristol',
      name: 'Bristol',
      latitude: 51.5074,
      longitude: -2.5901,
    );

    expect(
      filterFullMapStations(
        stations: [bazias, bristol],
      ).map((station) => station.id),
      ['bazias', 'bristol'],
    );
    expect(
      filterFullMapStations(
        stations: [bazias, bristol],
        stationIds: const {'bristol'},
      ).map((station) => station.id),
      ['bristol'],
    );
  });

  test(
    'UK physical location does not remove 23 canonical Danube station candidates',
    () {
      const physicalLocation = LatLng(51.4545, -2.5879);
      final stations = _canonicalDanubeStations();

      final candidates = filterFullMapStations(stations: stations);

      expect(physicalLocation, const LatLng(51.4545, -2.5879));
      expect(candidates, hasLength(23));
      expect(candidates, orderedEquals(stations));
      expect(candidates.every((station) => station.longitude > 20), isTrue);
    },
  );

  test(
    'station coordinates stay independent without replacing UK physical GPS',
    () {
      const physicalLocation = LatLng(51.4545, -2.5879);
      final candidates = filterFullMapStations(
        stations: _canonicalDanubeStations(),
      );

      expect(candidates.first.id, 'bazias');
      expect(candidates.first.latitude, 44.8167);
      expect(candidates.first.longitude, 21.3944);
      expect(physicalLocation.latitude, 51.4545);
      expect(physicalLocation.longitude, -2.5879);
      expect(
        candidates.where(
          (station) =>
              station.latitude == physicalLocation.latitude &&
              station.longitude == physicalLocation.longitude,
        ),
        isEmpty,
      );
    },
  );

  test('full-map trend and temporary highlight colors stay canonical', () {
    expect(
      MapFeatureRegistry.stationTrendColor(
        _station(
          id: 'rising',
          name: 'Rising',
          latitude: 44,
          longitude: 22,
          trend: WaterTrend.rising,
        ),
      ),
      const Color(0xFF2F8CFF),
    );
    expect(
      MapFeatureRegistry.stationTrendColor(
        _station(
          id: 'stable',
          name: 'Stable',
          latitude: 44,
          longitude: 22,
          trend: WaterTrend.stable,
        ),
      ),
      const Color(0xFF67D04B),
    );
    expect(
      MapFeatureRegistry.stationTrendColor(
        _station(
          id: 'falling',
          name: 'Falling',
          latitude: 44,
          longitude: 22,
          trend: WaterTrend.falling,
        ),
      ),
      const Color(0xFFFF5A67),
    );
    expect(
      MapFeatureRegistry.stationTrendColor(
        _station(
          id: 'unknown',
          name: 'Unknown',
          latitude: 44,
          longitude: 22,
          hasKnownTrend: false,
        ),
      ),
      const Color(0xFF78909C),
    );
    expect(fullMapTemporaryStationHighlightColor, const Color(0xFFFFD166));
  });

  test('approved community filters apply category and real coordinates', () {
    final now = DateTime(2026, 8, 4);
    final reports = [
      CommunityPost(
        id: 'near-low-water',
        userId: 'user',
        type: CommunityPostType.report,
        title: 'Low water',
        body: '',
        createdAt: now,
        authorName: 'Tester',
        reportCategory: ReportCategory.lowWater,
        latitude: 44.817,
        longitude: 21.395,
      ),
      CommunityPost(
        id: 'near-access',
        userId: 'user',
        type: CommunityPostType.report,
        title: 'Access',
        body: '',
        createdAt: now,
        authorName: 'Tester',
        reportCategory: ReportCategory.accessBlocked,
        latitude: 44.818,
        longitude: 21.396,
      ),
      CommunityPost(
        id: 'missing-location',
        userId: 'user',
        type: CommunityPostType.report,
        title: 'No location',
        body: '',
        createdAt: now,
        authorName: 'Tester',
        reportCategory: ReportCategory.lowWater,
      ),
    ];

    expect(
      filterFullMapReports(
        reports: reports,
        center: const LatLng(44.8167, 21.3944),
        radiusKm: 25,
        categories: const {ReportCategory.lowWater},
      ).map((report) => report.id),
      ['near-low-water'],
    );
  });

  test('community reports remain radius-filtered around UK location', () {
    final now = DateTime(2026, 8, 10);
    final reports = [
      CommunityPost(
        id: 'danube-report',
        userId: 'user',
        type: CommunityPostType.report,
        title: 'Danube report',
        body: '',
        createdAt: now,
        authorName: 'Tester',
        reportCategory: ReportCategory.lowWater,
        latitude: 44.8167,
        longitude: 21.3944,
      ),
      CommunityPost(
        id: 'bristol-report',
        userId: 'user',
        type: CommunityPostType.report,
        title: 'Bristol report',
        body: '',
        createdAt: now,
        authorName: 'Tester',
        reportCategory: ReportCategory.lowWater,
        latitude: 51.4545,
        longitude: -2.5879,
      ),
    ];

    expect(
      filterFullMapReports(
        reports: reports,
        center: const LatLng(51.4545, -2.5879),
        radiusKm: 100,
        categories: const {ReportCategory.lowWater},
      ).map((report) => report.id),
      ['bristol-report'],
    );
  });

  testWidgets('canonical station preview exposes every approved action', (
    tester,
  ) async {
    var close = 0;
    var details = 0;
    var favorite = 0;
    var alert = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: FullMapPinPreviewCard(
            station: _station(
              id: 'bazias',
              name: 'Baziaș',
              latitude: 44.8167,
              longitude: 21.3944,
            ),
            onClose: () => close++,
            onDetails: () => details++,
            onFavorite: () => favorite++,
            onAlert: () => alert++,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('full-map-pin-preview')), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.tap(find.byTooltip('Adaugă la favorite'));
    await tester.tap(find.byTooltip('Alertă'));
    await tester.tap(find.text('Vezi detalii'));
    expect((close, details, favorite, alert), (1, 1, 1, 1));
  });
}

Station _station({
  required String id,
  required String name,
  required double latitude,
  required double longitude,
  WaterTrend trend = WaterTrend.rising,
  bool hasKnownTrend = true,
}) => Station(
  id: id,
  name: name,
  river: 'Dunărea',
  level: 548,
  trend: trend,
  latitude: latitude,
  longitude: longitude,
  lastUpdate: DateTime(2026, 8, 4),
  hasWaterLevel: true,
  hasKnownTrend: hasKnownTrend,
  waterLevelSource: 'AFDJ',
);

List<Station> _canonicalDanubeStations() {
  const fixtures = <(String, double, double)>[
    ('bazias', 44.8167, 21.3944),
    ('moldova-veche', 44.7250, 21.6630),
    ('drencova', 44.6330, 21.9770),
    ('orsova', 44.7250, 22.3960),
    ('drobeta-turnu-severin', 44.6360, 22.6590),
    ('gruia', 44.2670, 22.7040),
    ('cetate', 44.1010, 22.9500),
    ('calafat', 43.9900, 22.9400),
    ('rast', 43.8830, 23.2830),
    ('bechet', 43.7800, 23.9570),
    ('corabia', 43.7750, 24.5000),
    ('turnu-magurele', 43.7460, 24.8750),
    ('zimnicea', 43.6560, 25.3640),
    ('giurgiu', 43.9040, 25.9690),
    ('oltenita', 44.0860, 26.6370),
    ('calarasi', 44.2050, 27.3300),
    ('cernavoda', 44.3390, 28.0340),
    ('harsova', 44.6850, 27.9500),
    ('braila', 45.2690, 27.9570),
    ('galati', 45.4350, 28.0500),
    ('isaccea', 45.2690, 28.4590),
    ('tulcea', 45.1780, 28.8010),
    ('sulina', 45.1590, 29.6530),
  ];

  return [
    for (final (id, latitude, longitude) in fixtures)
      _station(id: id, name: id, latitude: latitude, longitude: longitude),
  ];
}
