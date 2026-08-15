import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class CurrentDeviceLocation {
  const CurrentDeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.observedAt,
    this.label,
    this.locality,
    this.region,
    this.countryCode,
    this.headingDegrees,
    this.speedMetersPerSecond,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime observedAt;
  final String? label;
  final String? locality;
  final String? region;
  final String? countryCode;
  final double? headingDegrees;
  final double? speedMetersPerSecond;

  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (latitude != 0 || longitude != 0);

  bool isFreshAt(
    DateTime now, {
    Duration maximumAge = const Duration(minutes: 5),
  }) {
    final age = now.difference(observedAt);
    return !age.isNegative && age <= maximumAge;
  }

  bool isValidLastKnownAt(
    DateTime now, {
    Duration maximumAge = const Duration(minutes: 30),
  }) => hasValidCoordinates && isFreshAt(now, maximumAge: maximumAge);

  CurrentDeviceLocation copyWith({
    String? label,
    String? locality,
    String? region,
    String? countryCode,
  }) => CurrentDeviceLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    observedAt: observedAt,
    label: label ?? this.label,
    locality: locality ?? this.locality,
    region: region ?? this.region,
    countryCode: countryCode ?? this.countryCode,
    headingDegrees: headingDegrees,
    speedMetersPerSecond: speedMetersPerSecond,
  );
}

abstract interface class DeviceLocationSource {
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  });
}

abstract interface class ProgressiveDeviceLocationSource {
  Future<CurrentDeviceLocation?> getLastKnownCoordinates();

  Future<CurrentDeviceLocation> getCurrentCoordinates();

  Future<DeviceLocality?> resolveDeviceLocality(
    CurrentDeviceLocation location, {
    required String languageCode,
  });
}

class DeviceLocality {
  const DeviceLocality({
    required this.label,
    this.locality,
    this.region,
    this.countryCode,
  });

  final String label;
  final String? locality;
  final String? region;
  final String? countryCode;
}

class LocationFailure implements Exception {
  const LocationFailure(this.reason);

  final LocationFailureReason reason;
}

class LocationService
    implements DeviceLocationSource, ProgressiveDeviceLocationSource {
  const LocationService();

  Future<Position> determinePosition() async {
    final cachedPosition = _cachedPosition;
    final cachedAt = _cachedAt;
    if (cachedPosition != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 2)) {
      return cachedPosition;
    }

    final activeRequest = _activeRequest;
    if (activeRequest != null) {
      return activeRequest;
    }

    final request = _determinePosition();
    _activeRequest = request;

    try {
      final position = await request;
      _cachedPosition = position;
      _cachedAt = DateTime.now();
      return position;
    } finally {
      _activeRequest = null;
    }
  }

  static Position? _cachedPosition;
  static DateTime? _cachedAt;
  static Future<Position>? _activeRequest;
  static final Map<String, _ResolvedLocationLabel> _resolvedLabels = {};
  static final Map<String, Future<DeviceLocality?>> _activeLabelRequests = {};

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) async {
    final coordinates = await getCurrentCoordinates();
    final locality = await resolveDeviceLocality(
      coordinates,
      languageCode: languageCode,
    );
    return coordinates.copyWith(
      label: locality?.label,
      locality: locality?.locality,
      region: locality?.region,
      countryCode: locality?.countryCode,
    );
  }

  @override
  Future<CurrentDeviceLocation?> getLastKnownCoordinates() async {
    final cachedPosition = _cachedPosition;
    if (cachedPosition != null) return _deviceLocationFrom(cachedPosition);

    await _ensureLocationAvailable();
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null ? null : _deviceLocationFrom(position);
    } on LocationFailure {
      rethrow;
    } on Exception {
      return null;
    }
  }

  @override
  Future<CurrentDeviceLocation> getCurrentCoordinates() async {
    final position = await determinePosition();
    return _deviceLocationFrom(position);
  }

  /// Foreground-only high-accuracy stream used by explicit navigation modes.
  ///
  /// This stream is intentionally not started by normal map/location refresh.
  /// The caller owns the subscription lifecycle and must cancel it on STOP,
  /// when leaving the map, and when the app leaves the foreground.
  Stream<CurrentDeviceLocation> watchNavigationCoordinates() async* {
    await _ensureLocationAvailable();

    await for (final position in Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    )) {
      _cachedPosition = position;
      _cachedAt = DateTime.now();
      yield _deviceLocationFrom(position);
    }
  }

  static CurrentDeviceLocation _deviceLocationFrom(Position position) {
    final heading = position.heading.isFinite && position.heading >= 0
        ? position.heading
        : null;
    final speed = position.speed.isFinite && position.speed >= 0
        ? position.speed
        : null;
    return CurrentDeviceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      observedAt: position.timestamp,
      headingDegrees: heading,
      speedMetersPerSecond: speed,
    );
  }

  @override
  Future<DeviceLocality?> resolveDeviceLocality(
    CurrentDeviceLocation location, {
    required String languageCode,
  }) async {
    return _resolveLocality(
      latitude: location.latitude,
      longitude: location.longitude,
      languageCode: languageCode,
    );
  }

  Future<String?> resolveLocalityRegion(
    Position position, {
    required String languageCode,
  }) async {
    return (await _resolveLocality(
      latitude: position.latitude,
      longitude: position.longitude,
      languageCode: languageCode,
    ))?.label;
  }

  Future<DeviceLocality?> _resolveLocality({
    required double latitude,
    required double longitude,
    required String languageCode,
  }) {
    final cacheKey = _labelCacheKey(latitude, longitude, languageCode);
    final cached = _resolvedLabels[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.resolvedAt) <
            const Duration(hours: 6)) {
      return Future<DeviceLocality?>.value(cached.locality);
    }

    final active = _activeLabelRequests[cacheKey];
    if (active != null) return active;

    late final Future<DeviceLocality?> request;
    request =
        _fetchLocality(
          latitude: latitude,
          longitude: longitude,
          languageCode: languageCode,
          cached: cached,
          cacheKey: cacheKey,
        ).whenComplete(() {
          if (identical(_activeLabelRequests[cacheKey], request)) {
            _activeLabelRequests.remove(cacheKey);
          }
        });
    _activeLabelRequests[cacheKey] = request;
    return request;
  }

  Future<DeviceLocality?> _fetchLocality({
    required double latitude,
    required double longitude,
    required String languageCode,
    required _ResolvedLocationLabel? cached,
    required String cacheKey,
  }) async {
    try {
      final placemarks = await Geocoding(locale: Locale(languageCode))
          .placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 8));
      if (placemarks.isEmpty) return null;

      final placemark = placemarks.first;
      final locality = _firstNonEmpty([
        placemark.locality,
        placemark.subLocality,
      ]);
      if (locality == null) return null;

      final normalizedLocality = locality.toLowerCase();
      final region = _firstNonEmpty(
        [
          placemark.subAdministrativeArea,
          placemark.administrativeArea,
        ].where((value) => value?.trim().toLowerCase() != normalizedLocality),
      );
      final label = region == null ? locality : '$locality, $region';
      final resolved = DeviceLocality(
        label: label,
        locality: locality,
        region: region,
        countryCode: placemark.isoCountryCode?.trim().toUpperCase(),
      );
      _resolvedLabels[cacheKey] = _ResolvedLocationLabel(
        locality: resolved,
        resolvedAt: DateTime.now(),
      );
      return resolved;
    } on Exception {
      return cached?.locality;
    }
  }

  static String _labelCacheKey(
    double latitude,
    double longitude,
    String languageCode,
  ) =>
      '${latitude.toStringAsFixed(2)}:'
      '${longitude.toStringAsFixed(2)}:'
      '${languageCode.toLowerCase()}';

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  Future<Position> _determinePosition() async {
    try {
      await _ensureLocationAvailable();

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
    } on LocationFailure {
      rethrow;
    } on Exception {
      throw const LocationFailure(LocationFailureReason.unavailable);
    }
  }

  Future<void> _ensureLocationAvailable() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationFailureReason.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationFailure(LocationFailureReason.permissionDenied);
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureReason.permissionDeniedForever,
      );
    }
  }
}

class _ResolvedLocationLabel {
  const _ResolvedLocationLabel({
    required this.locality,
    required this.resolvedAt,
  });

  final DeviceLocality locality;
  final DateTime resolvedAt;
}
