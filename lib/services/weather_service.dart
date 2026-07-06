import '../models/station.dart';
import '../models/weather.dart';
import '../repositories/weather_repository.dart';
import 'astronomy_service.dart';
import 'location_service.dart';
import 'water_service.dart';

class WeatherService {
  WeatherService({
    WeatherRepository? repository,
    LocationService? locationService,
    WaterService? waterService,
  }) : _repository = repository ?? const WeatherRepository(),
       _locationService = locationService ?? const LocationService(),
       _waterService = waterService ?? WaterService();

  static const cacheDuration = Duration(minutes: 15);
  static const _defaultRomaniaCoordinates = _Coordinates(43.90, 25.97);
  static final Map<String, _WeatherCacheEntry> _cache = {};

  final WeatherRepository _repository;
  final LocationService _locationService;
  final WaterService _waterService;

  static void clearCache() => _cache.clear();

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

  Future<WeatherData> getCurrentWeather({Station? fallbackStation}) async {
    final coordinates = await _resolveCoordinates(fallbackStation);
    final key =
        '${coordinates.latitude.toStringAsFixed(3)}:'
        '${coordinates.longitude.toStringAsFixed(3)}';
    final cached = _cache[key];

    if (cached != null &&
        DateTime.now().difference(cached.savedAt) < cacheDuration) {
      return cached.data;
    }

    try {
      final weather = await _repository.getCurrentWeather(
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
      );
      _cache[key] = _WeatherCacheEntry(weather, DateTime.now());
      return weather;
    } on Exception {
      if (cached != null) {
        return cached.data;
      }
      rethrow;
    }
  }

  Future<_Coordinates> _resolveCoordinates(Station? fallbackStation) async {
    try {
      final position = await _locationService.determinePosition();
      return _Coordinates(position.latitude, position.longitude);
    } on LocationFailure {
      final station = fallbackStation ?? await _firstStation();
      return station == null
          ? _defaultRomaniaCoordinates
          : _Coordinates(station.latitude, station.longitude);
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

class _WeatherCacheEntry {
  const _WeatherCacheEntry(this.data, this.savedAt);

  final WeatherData data;
  final DateTime savedAt;
}
