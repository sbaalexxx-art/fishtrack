import '../models/station.dart';
import '../models/weather.dart';
import '../core/cache/timed_cache.dart';
import '../repositories/weather_repository.dart';
import 'astronomy_service.dart';
import 'location_service.dart';
import 'water_service.dart';

enum WeatherLocationSource { gps, stationFallback, defaultFallback }

enum WeatherHomeStatus {
  available,
  staleFallback,
  locationUnavailable,
  providerError,
  unavailable,
}

class WeatherHomeResult {
  const WeatherHomeResult({
    required this.data,
    required this.latitude,
    required this.longitude,
    required this.locationSource,
    required this.status,
    required this.dataTimestamp,
    required this.dataAge,
    required this.isStale,
    required this.safeDiagnosticMessage,
  });

  final WeatherData? data;
  final double? latitude;
  final double? longitude;
  final WeatherLocationSource? locationSource;
  final WeatherHomeStatus status;
  final DateTime? dataTimestamp;
  final Duration? dataAge;
  final bool isStale;
  final String? safeDiagnosticMessage;
}

class _WeatherHomeCacheEntry {
  const _WeatherHomeCacheEntry({required this.result, required this.savedAt});

  final WeatherHomeResult result;
  final DateTime savedAt;
}

class WeatherService {
  WeatherService({
    WeatherRepository? repository,
    LocationService? locationService,
    WaterService? waterService,
  }) : _repository = repository ?? const WeatherRepository(),
       _locationService = locationService ?? const LocationService(),
       _waterService = waterService ?? WaterService();

  static const cacheDuration = Duration(minutes: 30);
  static final Map<String, TimedCache<WeatherData>> _cache = {};
  static final Map<String, _WeatherHomeCacheEntry> _homeCache = {};
  static final Map<String, Future<WeatherHomeResult>> _homeInFlight = {};
  static final Map<String, int> _homeKeyGenerations = {};
  static int _homeCacheEpoch = 0;

  final WeatherRepository _repository;
  final LocationService _locationService;
  final WaterService _waterService;

  static void clearCache() {
    _cache.clear();
    _homeCacheEpoch++;
    _homeCache.clear();
    _homeInFlight.clear();
    _homeKeyGenerations.clear();
  }

  Future<AstronomyContext> getAstronomyContext({
    Station? fallbackStation,
    DateTime? dateTime,
  }) async {
    final moon = const AstronomyService().moonPhase(dateTime ?? DateTime.now());
    try {
      final position = await _locationService.determinePosition();
      return const AstronomyService().calculate(
        dateTime: dateTime ?? DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on LocationFailure {
      final station = fallbackStation ?? _waterService.selectedStation;
      if (station == null) {
        return AstronomyContext.locationRequired(moon: moon);
      }
      return const AstronomyService().calculate(
        dateTime: dateTime ?? DateTime.now(),
        latitude: station.latitude,
        longitude: station.longitude,
      );
    } on Exception {
      return AstronomyContext.notAvailable(moon: moon);
    }
  }

  Future<WeatherData> getCurrentWeather({
    Station? fallbackStation,
    bool forceRefresh = false,
  }) async => (await getCurrentWeatherResult(
    fallbackStation: fallbackStation,
    forceRefresh: forceRefresh,
  )).value;

  Future<CacheResult<WeatherData>> getCurrentWeatherResult({
    Station? fallbackStation,
    bool forceRefresh = false,
  }) async {
    final coordinates = await _resolveCoordinates(fallbackStation);
    return _getWeatherForCoordinates(
      coordinates.latitude,
      coordinates.longitude,
      forceRefresh: forceRefresh,
    );
  }

  /// Loads weather for a station without consulting the device location.
  /// Home Weather deliberately keeps its GPS-first behaviour.
  Future<WeatherData> getWeatherForStation(
    Station station, {
    bool forceRefresh = false,
  }) async => (await getWeatherForStationResult(
    station,
    forceRefresh: forceRefresh,
  )).value;

  Future<CacheResult<WeatherData>> getWeatherForStationResult(
    Station station, {
    bool forceRefresh = false,
  }) {
    final latitude = station.latitude;
    final longitude = station.longitude;
    if (!_validCoordinates(latitude, longitude) ||
        (latitude == 0 && longitude == 0)) {
      return Future<CacheResult<WeatherData>>.error(
        const WeatherServiceException(
          'Station weather coordinates are invalid.',
        ),
      );
    }
    return _getWeatherForCoordinates(
      latitude,
      longitude,
      forceRefresh: forceRefresh,
    );
  }

  Future<CacheResult<WeatherData>> _getWeatherForCoordinates(
    double latitude,
    double longitude, {
    required bool forceRefresh,
  }) async {
    final key =
        '${latitude.toStringAsFixed(3)}:'
        '${longitude.toStringAsFixed(3)}';
    final cache = _cache.putIfAbsent(
      key,
      () => TimedCache<WeatherData>(duration: cacheDuration),
    );
    try {
      return await cache.get(
        () => _repository.getCurrentWeather(
          latitude: latitude,
          longitude: longitude,
        ),
        forceRefresh: forceRefresh,
      );
    } on Exception {
      throw const WeatherServiceException('Weather data is unavailable.');
    }
  }

  Future<WeatherHomeResult> getHomeWeatherResult({
    Station? fallbackStation,
    bool forceRefresh = false,
  }) {
    final key = _homeWeatherKey(fallbackStation);
    final now = DateTime.now();
    if (forceRefresh) {
      _homeCache.remove(key);
      _homeInFlight.remove(key);
      _homeKeyGenerations[key] = (_homeKeyGenerations[key] ?? 0) + 1;
    } else {
      final cached = _homeCache[key];
      if (cached != null && now.difference(cached.savedAt) < cacheDuration) {
        return Future<WeatherHomeResult>.value(
          _withCurrentDataAge(cached.result, now),
        );
      }
      final activeRequest = _homeInFlight[key];
      if (activeRequest != null) return activeRequest;
    }

    final requestEpoch = _homeCacheEpoch;
    final requestGeneration = _homeKeyGenerations[key] ?? 0;
    late final Future<WeatherHomeResult> request;
    request =
        _loadHomeWeatherResult(
              fallbackStation: fallbackStation,
              forceRefresh: forceRefresh,
            )
            .then((result) {
              if (_homeCacheEpoch == requestEpoch &&
                  (_homeKeyGenerations[key] ?? 0) == requestGeneration) {
                _homeCache[key] = _WeatherHomeCacheEntry(
                  result: result,
                  savedAt: DateTime.now(),
                );
              }
              return _withCurrentDataAge(result, DateTime.now());
            })
            .whenComplete(() {
              if (identical(_homeInFlight[key], request)) {
                _homeInFlight.remove(key);
              }
            });
    _homeInFlight[key] = request;
    return request;
  }

  /// Loads Home weather for the supplied canonical device coordinates.
  ///
  /// This path never substitutes a station or another remembered place.
  Future<WeatherHomeResult> getHomeWeatherResultForLocation({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) {
    if (!_validCoordinates(latitude, longitude)) {
      return Future<WeatherHomeResult>.value(
        const WeatherHomeResult(
          data: null,
          latitude: null,
          longitude: null,
          locationSource: null,
          status: WeatherHomeStatus.locationUnavailable,
          dataTimestamp: null,
          dataAge: null,
          isStale: false,
          safeDiagnosticMessage: 'No valid device coordinates available',
        ),
      );
    }
    final coordinates = _HomeCoordinates(
      latitude: latitude,
      longitude: longitude,
      source: WeatherLocationSource.gps,
    );
    final key =
        '${identityHashCode(_repository)}:device:'
        '${latitude.toStringAsFixed(3)}:${longitude.toStringAsFixed(3)}';
    final now = DateTime.now();
    if (forceRefresh) {
      _homeCache.remove(key);
      _homeInFlight.remove(key);
      _homeKeyGenerations[key] = (_homeKeyGenerations[key] ?? 0) + 1;
    } else {
      final cached = _homeCache[key];
      if (cached != null && now.difference(cached.savedAt) < cacheDuration) {
        return Future<WeatherHomeResult>.value(
          _withCurrentDataAge(cached.result, now),
        );
      }
      final activeRequest = _homeInFlight[key];
      if (activeRequest != null) return activeRequest;
    }

    final requestEpoch = _homeCacheEpoch;
    final requestGeneration = _homeKeyGenerations[key] ?? 0;
    late final Future<WeatherHomeResult> request;
    request =
        _loadHomeWeatherForCoordinates(coordinates, forceRefresh: forceRefresh)
            .then((result) {
              if (_homeCacheEpoch == requestEpoch &&
                  (_homeKeyGenerations[key] ?? 0) == requestGeneration) {
                _homeCache[key] = _WeatherHomeCacheEntry(
                  result: result,
                  savedAt: DateTime.now(),
                );
              }
              return _withCurrentDataAge(result, DateTime.now());
            })
            .whenComplete(() {
              if (identical(_homeInFlight[key], request)) {
                _homeInFlight.remove(key);
              }
            });
    _homeInFlight[key] = request;
    return request;
  }

  Future<WeatherHomeResult> _loadHomeWeatherResult({
    required Station? fallbackStation,
    required bool forceRefresh,
  }) async {
    final coordinates = await _resolveHomeCoordinates(fallbackStation);
    if (coordinates == null) {
      return const WeatherHomeResult(
        data: null,
        latitude: null,
        longitude: null,
        locationSource: null,
        status: WeatherHomeStatus.locationUnavailable,
        dataTimestamp: null,
        dataAge: null,
        isStale: false,
        safeDiagnosticMessage: 'No valid weather coordinates available',
      );
    }

    return _loadHomeWeatherForCoordinates(
      coordinates,
      forceRefresh: forceRefresh,
    );
  }

  Future<WeatherHomeResult> _loadHomeWeatherForCoordinates(
    _HomeCoordinates coordinates, {
    required bool forceRefresh,
  }) async {
    try {
      final cached = await _getHomeCachedWeather(
        coordinates,
        forceRefresh: forceRefresh,
      );
      final data = cached.value;
      if (!_hasUsableHomeData(data)) {
        return WeatherHomeResult(
          data: null,
          latitude: coordinates.latitude,
          longitude: coordinates.longitude,
          locationSource: coordinates.source,
          status: WeatherHomeStatus.unavailable,
          dataTimestamp: data.observedAt,
          dataAge: null,
          isStale: false,
          safeDiagnosticMessage: 'Weather response contains invalid values',
        );
      }
      return WeatherHomeResult(
        data: data,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        locationSource: coordinates.source,
        status: cached.isStaleFallback
            ? WeatherHomeStatus.staleFallback
            : WeatherHomeStatus.available,
        dataTimestamp: data.observedAt,
        dataAge: null,
        isStale: cached.isStaleFallback,
        safeDiagnosticMessage: cached.isStaleFallback
            ? 'Open-Meteo refresh failed; using cached data'
            : coordinates.safeDiagnosticMessage,
      );
    } on Exception catch (error) {
      return WeatherHomeResult(
        data: null,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        locationSource: coordinates.source,
        status: WeatherHomeStatus.providerError,
        dataTimestamp: null,
        dataAge: null,
        isStale: false,
        safeDiagnosticMessage:
            'Open-Meteo request failed (${error.runtimeType})',
      );
    }
  }

  Future<CacheResult<WeatherData>> _getHomeCachedWeather(
    _HomeCoordinates coordinates, {
    required bool forceRefresh,
  }) {
    final key =
        '${coordinates.latitude.toStringAsFixed(3)}:'
        '${coordinates.longitude.toStringAsFixed(3)}';
    final cache = _cache.putIfAbsent(
      key,
      () => TimedCache<WeatherData>(duration: cacheDuration),
    );
    return cache.get(
      () => _repository.getCurrentWeather(
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
      ),
      forceRefresh: forceRefresh,
    );
  }

  Future<_HomeCoordinates?> _resolveHomeCoordinates(
    Station? fallbackStation,
  ) async {
    Object? locationError;
    try {
      final position = await _locationService.determinePosition();
      if (_validCoordinates(position.latitude, position.longitude)) {
        return _HomeCoordinates(
          latitude: position.latitude,
          longitude: position.longitude,
          source: WeatherLocationSource.gps,
        );
      }
      locationError = const WeatherServiceException(
        'GPS returned invalid coordinates.',
      );
    } on LocationFailure catch (error) {
      locationError = error;
    } on Exception catch (error) {
      locationError = error;
    }

    final station = fallbackStation ?? await _firstStation();
    if (station != null &&
        _validCoordinates(station.latitude, station.longitude)) {
      return _HomeCoordinates(
        latitude: station.latitude,
        longitude: station.longitude,
        source: WeatherLocationSource.stationFallback,
        safeDiagnosticMessage:
            'GPS unavailable (${locationError.runtimeType}); using station',
      );
    }
    return null;
  }

  Future<_Coordinates> _resolveCoordinates(Station? fallbackStation) async {
    try {
      final position = await _locationService.determinePosition();
      return _Coordinates(position.latitude, position.longitude);
    } on LocationFailure {
      final station = fallbackStation ?? await _firstStation();
      if (station != null &&
          _validCoordinates(station.latitude, station.longitude) &&
          (station.latitude != 0 || station.longitude != 0)) {
        return _Coordinates(station.latitude, station.longitude);
      }
      throw const WeatherServiceException('Weather location is unavailable.');
    }
  }

  Future<Station?> _firstStation() async {
    try {
      final stations = await _waterService.getStations();
      return stations.isEmpty ? null : stations.first;
    } on Exception {
      return null;
    }
  }

  String _homeWeatherKey(Station? fallbackStation) {
    final stationKey = fallbackStation == null
        ? 'auto'
        : '${fallbackStation.id}:'
              '${fallbackStation.latitude.toStringAsFixed(4)}:'
              '${fallbackStation.longitude.toStringAsFixed(4)}';
    return '${identityHashCode(_repository)}:'
        '${identityHashCode(_locationService)}:$stationKey';
  }

  static WeatherHomeResult _withCurrentDataAge(
    WeatherHomeResult result,
    DateTime now,
  ) {
    final timestamp = result.dataTimestamp;
    final age = timestamp == null ? null : _nonNegativeAge(now, timestamp);
    return WeatherHomeResult(
      data: result.data,
      latitude: result.latitude,
      longitude: result.longitude,
      locationSource: result.locationSource,
      status: result.status,
      dataTimestamp: timestamp,
      dataAge: age,
      isStale: result.isStale,
      safeDiagnosticMessage: result.safeDiagnosticMessage,
    );
  }

  static bool _hasUsableHomeData(WeatherData data) =>
      data.temperature.isFinite &&
      data.humidity.isFinite &&
      data.windSpeed.isFinite &&
      data.windDirectionDegrees.isFinite &&
      data.precipitationProbability.isFinite &&
      data.observedAt.millisecondsSinceEpoch > 0;

  static bool _validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static Duration _nonNegativeAge(DateTime now, DateTime timestamp) {
    final age = now.difference(timestamp.toLocal());
    return age.isNegative ? Duration.zero : age;
  }
}

class WeatherServiceException implements Exception {
  const WeatherServiceException(this.message);

  final String message;
}

class _Coordinates {
  const _Coordinates(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class _HomeCoordinates {
  const _HomeCoordinates({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.safeDiagnosticMessage,
  });

  final double latitude;
  final double longitude;
  final WeatherLocationSource source;
  final String? safeDiagnosticMessage;
}
