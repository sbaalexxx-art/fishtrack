import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/map/pending_map_camera.dart';
import 'package:fishtrack/features/commercial_home/presentation/commercial_home_page.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/weather.dart';
import 'package:fishtrack/repositories/water_repository.dart';
import 'package:fishtrack/repositories/weather_repository.dart';
import 'package:fishtrack/screens/map_page.dart';
import 'package:fishtrack/services/community_service.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/services/weather_service.dart';
import 'package:fishtrack/widgets/home_premium/home_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CurrentDeviceLocation bristol;

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    WaterService.clearCache();
    WeatherService.clearCache();
    bristol = CurrentDeviceLocation(
      latitude: 51.4545,
      longitude: -2.5879,
      accuracyMeters: 7,
      observedAt: DateTime.now(),
      label: 'Bristol, England',
    );
  });

  test('Bristol device location survives remote Baziaș selection', () async {
    final container = ProviderContainer(
      overrides: [
        deviceLocationSourceProvider.overrideWithValue(
          _FixedDeviceLocationSource(bristol),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(currentLocationProvider.notifier)
        .refresh(languageCode: 'en');
    container
        .read(selectedContextProvider.notifier)
        .select(SelectedContext.fromStation(_bazias()));

    final current = container.read(currentLocationProvider).location!;
    expect((current.latitude, current.longitude), (51.4545, -2.5879));
    expect(container.read(selectedContextProvider)!.stationId, 'bazias');
  });

  test(
    'Paris search target changes camera request, not device state',
    () async {
      final container = ProviderContainer(
        overrides: [
          deviceLocationSourceProvider.overrideWithValue(
            _FixedDeviceLocationSource(bristol),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: 'en');

      final focus = MapFocusController();
      addTearDown(focus.dispose);
      focus.requestTarget(
        const RuntimeMapCameraTarget(
          source: 'global-search',
          entityId: 'paris',
          latitude: 48.8566,
          longitude: 2.3522,
          zoom: 13.5,
        ),
      );

      expect(focus.takePending()!.target.latitude, 48.8566);
      expect(
        container.read(currentLocationProvider).location!.latitude,
        51.4545,
      );
      expect(container.read(selectedContextProvider), isNull);
    },
  );

  test('My Location camera target restores canonical GPS coordinates', () {
    final coordinator = PendingMapCameraCoordinator();
    coordinator.request(
      const RuntimeMapCameraTarget(
        source: 'global-search',
        entityId: 'paris',
        latitude: 48.8566,
        longitude: 2.3522,
        zoom: 13.5,
      ),
    );

    coordinator.request(
      deviceLocationCameraTarget(
        latitude: bristol.latitude,
        longitude: bristol.longitude,
        zoom: 13.5,
      ),
    );

    expect(coordinator.activeTarget!.source, 'device-location');
    expect(coordinator.activeTarget!.latitude, bristol.latitude);
    expect(coordinator.activeTarget!.longitude, bristol.longitude);
  });

  test('Home header label comes from current location, not remote water', () {
    final selectedRemote = SelectedContext.fromStation(_bazias());

    expect(homeCurrentLocationLabel(bristol), 'Bristol, England');
    expect(
      homeCurrentLocationLabel(bristol),
      isNot(selectedRemote.primaryLabel),
    );
  });

  test('Home mini-map center comes from canonical current location state', () {
    final center = homeMapDeviceCenter(
      CurrentLocationState(
        status: CurrentLocationStatus.available,
        location: bristol,
      ),
    );

    expect(center, isNotNull);
    expect((center!.latitude, center.longitude), (51.4545, -2.5879));
  });

  test('Home weather uses device coordinates, not remote station', () async {
    final repository = _RecordingWeatherRepository();
    final service = WeatherService(repository: repository);

    final result = await service.getHomeWeatherResultForLocation(
      latitude: bristol.latitude,
      longitude: bristol.longitude,
    );

    expect(result.status, WeatherHomeStatus.available);
    expect(repository.requests.single, (51.4545, -2.5879));
    expect(
      repository.requests.single,
      isNot((_bazias().latitude, _bazias().longitude)),
    );
  });

  test('distant report is not selected as local Home report', () {
    final now = DateTime.now();
    final distant = CommunityPost(
      id: 'remote-report',
      userId: 'remote-user',
      type: CommunityPostType.report,
      title: 'Remote report',
      body: 'Not local to Bristol',
      createdAt: now,
      authorName: 'Remote angler',
      latitude: 44.8167,
      longitude: 21.3944,
      expiresAt: now.add(const Duration(hours: 4)),
    );

    expect(
      selectLocalHomeReport(
        [distant],
        latitude: bristol.latitude,
        longitude: bristol.longitude,
      ),
      isNull,
    );
  });

  test('UK automatic Water has no unrelated Romania fallback', () async {
    final service = WaterService(repository: _StationRepository([_bazias()]));
    await service.setAutomatic();

    final selection = await service.resolveHomeStationSelection(
      currentLatitude: bristol.latitude,
      currentLongitude: bristol.longitude,
    );

    expect(selection.mode, WaterStationSelectionMode.automatic);
    expect(selection.station, isNull);
  });
}

class _FixedDeviceLocationSource implements DeviceLocationSource {
  const _FixedDeviceLocationSource(this.location);

  final CurrentDeviceLocation location;

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) async => location;
}

class _StationRepository extends WaterRepository {
  const _StationRepository(this.stations);

  final List<Station> stations;

  @override
  Future<List<Station>> getStations() async => stations;

  @override
  Future<List<Station>> getFastStations() async => stations;
}

class _RecordingWeatherRepository extends WeatherRepository {
  final List<(double, double)> requests = [];

  @override
  Future<WeatherData> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    requests.add((latitude, longitude));
    return WeatherData(
      temperature: 18,
      condition: 'Cloudy',
      humidity: 70,
      windSpeed: 8,
      windGusts: 12,
      windDirectionDegrees: 240,
      precipitationProbability: 20,
      cloudCover: 60,
      observedAt: DateTime.now(),
      forecast: const [],
      hourlyForecast: const [],
      moonPhase: 'Waxing crescent',
      fishingActivity: FishingActivity.fair,
    );
  }
}

Station _bazias() => Station(
  id: 'bazias',
  name: 'Baziaș',
  river: 'Dunărea',
  level: 121,
  trend: WaterTrend.stable,
  latitude: 44.8167,
  longitude: 21.3944,
  lastUpdate: DateTime(2026, 8, 8),
  hasWaterLevel: true,
  hasKnownTrend: true,
  waterLevelSource: 'AFDJ',
);
