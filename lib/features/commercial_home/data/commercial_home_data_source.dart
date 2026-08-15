import '../../../core/context/environmental_context.dart';
import '../../../models/station.dart';
import '../../../services/community_service.dart';
import '../../../services/fishing_score_service.dart';
import '../../../services/location_service.dart';
import '../../../services/water_service.dart';
import '../../../services/weather_service.dart';

typedef CommercialLocalizedCopy =
    String Function({required String ro, required String en});
typedef CommercialSnapshotUpdate =
    void Function(CommercialHomeSnapshot snapshot);

enum CommercialHomeDomainStatus { loading, available, unavailable, error }

class CommercialHomeSnapshot {
  const CommercialHomeSnapshot({
    required this.station,
    required this.water,
    required this.weather,
    required this.score,
    required this.communityPosts,
    required this.loadedAt,
    this.selectionMode,
    this.currentLocation,
    this.environmentalContext,
    this.waterStatus = CommercialHomeDomainStatus.available,
    this.weatherStatus = CommercialHomeDomainStatus.available,
    this.scoreStatus = CommercialHomeDomainStatus.available,
    this.communityStatus = CommercialHomeDomainStatus.available,
  });

  final Station? station;
  final WaterUiResult? water;
  final WeatherHomeResult? weather;
  final FishingScoreResult? score;
  final List<CommunityPost> communityPosts;
  final DateTime loadedAt;
  final WaterStationSelectionMode? selectionMode;
  final CurrentDeviceLocation? currentLocation;
  final EnvironmentalContext? environmentalContext;
  final CommercialHomeDomainStatus waterStatus;
  final CommercialHomeDomainStatus weatherStatus;
  final CommercialHomeDomainStatus scoreStatus;
  final CommercialHomeDomainStatus communityStatus;
}

abstract interface class CommercialHomeDataSource {
  Stream<Station> get stationSelections;

  Future<CommercialHomeSnapshot> load({bool forceRefresh = false});
}

abstract interface class CurrentLocationAwareCommercialHomeDataSource {
  Future<CommercialHomeSnapshot> loadForCurrentLocation(
    CurrentDeviceLocation location, {
    bool forceRefresh = false,
  });
}

abstract interface class ProgressiveCommercialHomeDataSource {
  Future<CommercialHomeSnapshot> loadProgressively(
    CurrentDeviceLocation location, {
    required CommercialSnapshotUpdate onUpdate,
    bool forceRefresh = false,
  });
}

class LiveCommercialHomeDataSource
    implements
        CommercialHomeDataSource,
        CurrentLocationAwareCommercialHomeDataSource,
        ProgressiveCommercialHomeDataSource {
  LiveCommercialHomeDataSource({
    WaterService? waterService,
    WeatherService? weatherService,
    FishingDecisionProvider? scoreService,
    CommunityService? communityService,
    DeviceLocationSource? locationSource,
    Station? pinnedStation,
  }) : _waterService = waterService ?? WaterService(),
       _weatherService = weatherService ?? WeatherService(),
       _scoreService = scoreService ?? FishingScoreService(),
       _communityService = communityService ?? const CommunityService(),
       _pinnedStation = pinnedStation;

  final WaterService _waterService;
  final WeatherService _weatherService;
  final FishingDecisionProvider _scoreService;
  final CommunityService _communityService;
  final Station? _pinnedStation;

  @override
  Stream<Station> get stationSelections => _waterService.stationSelections;

  Future<T?> _safe<T>(Future<T?> request) async {
    try {
      return await request;
    } on Exception {
      return null;
    }
  }

  @override
  Future<CommercialHomeSnapshot> load({bool forceRefresh = false}) async {
    // This service is not a physical-location owner.
    // Canonical device GPS is supplied by currentLocationProvider through
    // loadForCurrentLocation/loadProgressively.
    //
    // A pinned station may still supply explicit Water context, but it must
    // never be fabricated into CurrentDeviceLocation.
    if (_pinnedStation == null) {
      return _loadForUnavailableLocation(forceRefresh: forceRefresh);
    }

    return _loadResolvedLocation(null, forceRefresh: forceRefresh);
  }

  @override
  Future<CommercialHomeSnapshot> loadForCurrentLocation(
    CurrentDeviceLocation location, {
    bool forceRefresh = false,
  }) => _loadResolvedLocation(location, forceRefresh: forceRefresh);

  @override
  Future<CommercialHomeSnapshot> loadProgressively(
    CurrentDeviceLocation location, {
    required CommercialSnapshotUpdate onUpdate,
    bool forceRefresh = false,
  }) => _loadResolvedLocation(
    location,
    forceRefresh: forceRefresh,
    onUpdate: onUpdate,
  );

  Future<CommercialHomeSnapshot> _loadResolvedLocation(
    CurrentDeviceLocation? location, {
    required bool forceRefresh,
    CommercialSnapshotUpdate? onUpdate,
  }) async {
    final pinnedStation = _pinnedStation;

    if (pinnedStation == null &&
        (location == null || !location.hasValidCoordinates)) {
      return _loadForUnavailableLocation(forceRefresh: forceRefresh);
    }

    WaterHomeCachedSnapshot? persisted;
    if (!forceRefresh) {
      persisted = await _safe(_waterService.restorePersistedHomeSnapshot());
    }

    final selection = pinnedStation == null
        ? await _safe(
            _waterService.resolveHomeStationSelection(
              currentLatitude: location!.latitude,
              currentLongitude: location.longitude,
            ),
          )
        : null;
    final station = pinnedStation ?? selection?.station;
    final context = pinnedStation == null
        ? EnvironmentalContext(
            source: EnvironmentalContextSource.deviceGps,
            latitude: location!.latitude,
            longitude: location.longitude,
            observedAt: location.observedAt,
            displayLabel: location.label,
            locality: location.locality,
            region: location.region,
            countryCode: location.countryCode,
          )
        : EnvironmentalContext(
            source: EnvironmentalContextSource.selectedStation,
            latitude: pinnedStation.latitude,
            longitude: pinnedStation.longitude,
            observedAt: DateTime.now(),
            displayLabel: '${pinnedStation.name}, ${pinnedStation.river}',
            stationId: pinnedStation.id,
            stationName: pinnedStation.name,
            waterName: pinnedStation.river,
          );
    final persistedForStation =
        station != null && persisted?.station.id == station.id
        ? persisted
        : null;
    WaterUiResult? water = station == null
        ? null
        : _waterService.cachedWaterUiResult(station, limit: 72) ??
              persistedForStation?.result;
    WeatherHomeResult? weather;
    FishingScoreResult? score;
    List<CommunityPost> communityPosts = const <CommunityPost>[];
    var waterStatus = station == null
        ? CommercialHomeDomainStatus.unavailable
        : water == null
        ? CommercialHomeDomainStatus.loading
        : CommercialHomeDomainStatus.available;
    var weatherStatus = CommercialHomeDomainStatus.loading;
    var scoreStatus = CommercialHomeDomainStatus.loading;
    var communityStatus = CommercialHomeDomainStatus.loading;

    CommercialHomeSnapshot snapshot() => CommercialHomeSnapshot(
      station: station,
      water: water,
      weather: weather,
      score: score,
      communityPosts: communityPosts,
      loadedAt: DateTime.now(),
      selectionMode: selection?.mode,
      currentLocation: location,
      environmentalContext: context,
      waterStatus: waterStatus,
      weatherStatus: weatherStatus,
      scoreStatus: scoreStatus,
      communityStatus: communityStatus,
    );
    void publish() => onUpdate?.call(snapshot());
    publish();

    final localScoreStation =
        station != null &&
            location != null &&
            WaterService.isStationWithinHomeRadius(
              station,
              latitude: location.latitude,
              longitude: location.longitude,
            )
        ? station
        : null;

    Future<void> loadWater() async {
      if (station == null) return;
      try {
        water = await _waterService.getWaterUiResult(
          station,
          limit: 72,
          forceRefresh: forceRefresh,
        );
        waterStatus = CommercialHomeDomainStatus.available;
      } on Exception {
        waterStatus = water == null
            ? CommercialHomeDomainStatus.error
            : CommercialHomeDomainStatus.available;
      }
      publish();
    }

    Future<void> loadWeather() async {
      try {
        weather = await _weatherService.getHomeWeatherResultForLocation(
          latitude: context.latitude,
          longitude: context.longitude,
          forceRefresh: forceRefresh,
        );
        weatherStatus = weather == null
            ? CommercialHomeDomainStatus.unavailable
            : CommercialHomeDomainStatus.available;
      } on Exception {
        weatherStatus = CommercialHomeDomainStatus.error;
      }
      publish();
    }

    Future<void> loadScore() async {
      try {
        final weatherData = weather?.data;
        final scoreService = _scoreService;
        if (scoreService is FishingScoreService && weatherData != null) {
          score = scoreService.calculateFrom(
            weather: weatherData,
            station: station,
            history: water?.history ?? const [],
            posts: communityPosts,
            communityAvailable:
                communityStatus == CommercialHomeDomainStatus.available,
            catchesAvailable:
                communityStatus == CommercialHomeDomainStatus.available,
            localTime: DateTime.now(),
          );
        } else {
          score = _scoreService is LocationAwareFishingDecisionProvider
              ? await (_scoreService as LocationAwareFishingDecisionProvider)
                    .calculateForLocation(
                      latitude: context.latitude,
                      longitude: context.longitude,
                      localStation: localScoreStation,
                      forceRefresh: forceRefresh,
                    )
              : localScoreStation == null
              ? const FishingScoreResult.notEnough()
              : await _scoreService.calculate(
                  fallbackStation: localScoreStation,
                  forceRefresh: forceRefresh,
                );
        }
        scoreStatus = score?.hasEnoughData == true
            ? CommercialHomeDomainStatus.available
            : CommercialHomeDomainStatus.unavailable;
      } on Exception {
        scoreStatus = CommercialHomeDomainStatus.error;
      }
      publish();
    }

    Future<void> loadCommunity() async {
      try {
        communityPosts = await _communityService.getFeed(
          forceRefresh: forceRefresh,
        );
        communityStatus = CommercialHomeDomainStatus.available;
      } on Exception {
        communityStatus = CommercialHomeDomainStatus.error;
      }
      publish();
    }

    await Future.wait<void>([loadWater(), loadWeather(), loadCommunity()]);
    await loadScore();
    return snapshot();
  }

  Future<CommercialHomeSnapshot> _loadForUnavailableLocation({
    required bool forceRefresh,
  }) async {
    final communityPosts = await _safe(
      _communityService.getFeed(forceRefresh: forceRefresh),
    );
    return CommercialHomeSnapshot(
      station: null,
      water: null,
      weather: const WeatherHomeResult(
        data: null,
        latitude: null,
        longitude: null,
        locationSource: null,
        status: WeatherHomeStatus.locationUnavailable,
        dataTimestamp: null,
        dataAge: null,
        isStale: false,
        safeDiagnosticMessage: 'Current device location is unavailable',
      ),
      score: const FishingScoreResult.notEnough(),
      communityPosts: communityPosts ?? const <CommunityPost>[],
      loadedAt: DateTime.now(),
    );
  }
}
