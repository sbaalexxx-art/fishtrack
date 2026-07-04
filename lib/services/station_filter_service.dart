import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/station.dart';

class StationFilters {
  const StationFilters({
    this.query = '',
    this.waterBodyType,
    this.species,
    this.radiusKm,
    this.minimumWaterLevel,
    this.maximumWaterLevel,
    this.trends = const {},
    this.difficulty,
    this.favoritesOnly = false,
  });

  final String query;
  final WaterBodyType? waterBodyType;
  final String? species;
  final double? radiusKm;
  final double? minimumWaterLevel;
  final double? maximumWaterLevel;
  final Set<WaterTrend> trends;
  final FishingDifficulty? difficulty;
  final bool favoritesOnly;

  StationFilters withQuery(String value) => StationFilters(
    query: value,
    waterBodyType: waterBodyType,
    species: species,
    radiusKm: radiusKm,
    minimumWaterLevel: minimumWaterLevel,
    maximumWaterLevel: maximumWaterLevel,
    trends: trends,
    difficulty: difficulty,
    favoritesOnly: favoritesOnly,
  );

  bool get hasAdvancedFilters =>
      waterBodyType != null ||
      species != null ||
      radiusKm != null ||
      minimumWaterLevel != null ||
      maximumWaterLevel != null ||
      trends.isNotEmpty ||
      difficulty != null ||
      favoritesOnly;
}

class StationFilterService {
  StationFilterService._();
  static final StationFilterService instance = StationFilterService._();

  final ValueNotifier<StationFilters> filters = ValueNotifier(
    const StationFilters(),
  );
  double? _latitude;
  double? _longitude;

  void update(StationFilters value) => filters.value = value;
  void updateQuery(String query) =>
      filters.value = filters.value.withQuery(query);
  void reset() => filters.value = const StationFilters();

  void setCurrentLocation(double latitude, double longitude) {
    _latitude = latitude;
    _longitude = longitude;
    filters.value = filters.value.withQuery(filters.value.query);
  }

  List<Station> apply(List<Station> stations) {
    final value = filters.value;
    final query = value.query.trim().toLowerCase();
    return stations
        .where((station) {
          if (query.isNotEmpty &&
              !station.name.toLowerCase().contains(query) &&
              !station.river.toLowerCase().contains(query) &&
              !station.species.any(
                (item) => item.toLowerCase().contains(query),
              )) {
            return false;
          }
          if (value.waterBodyType != null &&
              station.waterBodyType != value.waterBodyType) {
            return false;
          }
          if (value.species != null &&
              !station.species.any(
                (item) => item.toLowerCase() == value.species!.toLowerCase(),
              )) {
            return false;
          }
          if (value.minimumWaterLevel != null &&
              station.level < value.minimumWaterLevel!) {
            return false;
          }
          if (value.maximumWaterLevel != null &&
              station.level > value.maximumWaterLevel!) {
            return false;
          }
          if (value.trends.isNotEmpty &&
              !value.trends.contains(station.trend)) {
            return false;
          }
          if (value.difficulty != null &&
              station.difficulty != value.difficulty) {
            return false;
          }
          if (value.favoritesOnly && !station.isFavorite) {
            return false;
          }
          if (value.radiusKm != null &&
              _latitude != null &&
              _longitude != null) {
            final distance = Geolocator.distanceBetween(
              _latitude!,
              _longitude!,
              station.latitude,
              station.longitude,
            );
            if (distance > value.radiusKm! * 1000) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false);
  }
}
