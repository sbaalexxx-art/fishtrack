import 'package:flutter/foundation.dart';

enum EnvironmentalContextSource {
  deviceGps,
  searchedPlace,
  mapCamera,
  selectedWater,
  selectedStation,
}

@immutable
class EnvironmentalContext {
  const EnvironmentalContext({
    required this.source,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    this.displayLabel,
    this.locality,
    this.region,
    this.countryCode,
    this.waterId,
    this.waterName,
    this.stationId,
    this.stationName,
  });

  final EnvironmentalContextSource source;
  final double latitude;
  final double longitude;
  final DateTime observedAt;
  final String? displayLabel;
  final String? locality;
  final String? region;
  final String? countryCode;
  final String? waterId;
  final String? waterName;
  final String? stationId;
  final String? stationName;

  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (latitude != 0 || longitude != 0);

  String get contextKey => <String>[
    source.name,
    latitude.toStringAsFixed(5),
    longitude.toStringAsFixed(5),
    waterId ?? '-',
    stationId ?? '-',
  ].join(':');

  String? get primaryLabel =>
      stationName ?? waterName ?? displayLabel ?? locality;
}

enum ContentRegionSource { deviceGps, explicitSelection }

@immutable
class ContentRegion {
  const ContentRegion({
    required this.countryCode,
    required this.derivedAt,
    this.region,
    this.source = ContentRegionSource.deviceGps,
  });

  final String countryCode;
  final String? region;
  final DateTime derivedAt;
  final ContentRegionSource source;

  bool get isExplicit => source == ContentRegionSource.explicitSelection;
}

@immutable
class LocalContentContext {
  const LocalContentContext({
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.observedAt,
  });

  final double latitude;
  final double longitude;
  final double radiusKm;
  final DateTime observedAt;
}
