import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/location_service.dart';
import 'environmental_context.dart';

enum CurrentLocationStatus {
  idle,
  locating,
  cached,
  available,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

enum CurrentLocalityStatus {
  unknown,
  resolving,
  cached,
  available,
  unavailable,
}

class CurrentLocationState {
  const CurrentLocationState({
    this.status = CurrentLocationStatus.idle,
    this.localityStatus = CurrentLocalityStatus.unknown,
    this.location,
  });

  final CurrentLocationStatus status;
  final CurrentLocalityStatus localityStatus;
  final CurrentDeviceLocation? location;

  bool get isLocating => status == CurrentLocationStatus.locating;
  bool get hasUsableLocation =>
      location?.hasValidCoordinates == true &&
      switch (status) {
        CurrentLocationStatus.available => location!.isFreshAt(DateTime.now()),
        CurrentLocationStatus.cached => location!.isValidLastKnownAt(
          DateTime.now(),
        ),
        _ => false,
      };

  CurrentLocationState copyWith({
    CurrentLocationStatus? status,
    CurrentLocalityStatus? localityStatus,
    CurrentDeviceLocation? location,
  }) => CurrentLocationState(
    status: status ?? this.status,
    localityStatus: localityStatus ?? this.localityStatus,
    location: location ?? this.location,
  );
}

final deviceLocationSourceProvider = Provider<DeviceLocationSource>(
  (_) => const LocationService(),
);

class CurrentLocationController extends Notifier<CurrentLocationState> {
  static const _cachedLatitudeKey = 'current_locality_v1_latitude';
  static const _cachedLongitudeKey = 'current_locality_v1_longitude';
  static const _cachedLabelKey = 'current_locality_v1_label';
  static const _cachedLocalityKey = 'current_locality_v1_locality';
  static const _cachedRegionKey = 'current_locality_v1_region';
  static const _cachedCountryKey = 'current_locality_v1_country';
  static const _cachedResolvedAtKey = 'current_locality_v1_resolved_at';
  static const _maximumCachedLocalityAge = Duration(days: 30);
  static const _maximumLocalityReuseDistanceKm = 3.0;

  Future<CurrentLocationState>? _activeRequest;
  int _requestGeneration = 0;

  @override
  CurrentLocationState build() => const CurrentLocationState();

  Future<CurrentLocationState> refresh({
    required String languageCode,
    bool force = false,
  }) {
    final active = _activeRequest;
    if (active != null) return active;
    final existing = state.location;
    if (!force &&
        state.status == CurrentLocationStatus.available &&
        existing != null &&
        existing.isFreshAt(DateTime.now())) {
      return Future<CurrentLocationState>.value(state);
    }

    late final Future<CurrentLocationState> request;
    request = _refresh(languageCode).whenComplete(() {
      if (identical(_activeRequest, request)) _activeRequest = null;
    });
    _activeRequest = request;
    return request;
  }

  Future<CurrentLocationState> _refresh(String languageCode) async {
    final generation = ++_requestGeneration;
    final existing = state.location;
    state = state.copyWith(status: CurrentLocationStatus.locating);
    try {
      final source = ref.read(deviceLocationSourceProvider);
      if (source is ProgressiveDeviceLocationSource) {
        final progressive = source as ProgressiveDeviceLocationSource;
        final persistedLocality = await _restoreCachedLocality();
        final lastKnown = await progressive.getLastKnownCoordinates();
        if (lastKnown?.isValidLastKnownAt(DateTime.now()) == true) {
          final resolvedLastKnown = _withCanonicalLocality(
            lastKnown!,
            candidates: [existing, persistedLocality?.asLocation],
          );
          state = CurrentLocationState(
            status: CurrentLocationStatus.cached,
            localityStatus: _hasLocality(resolvedLastKnown)
                ? CurrentLocalityStatus.cached
                : CurrentLocalityStatus.resolving,
            location: resolvedLastKnown,
          );
          unawaited(
            _resolveLocality(
              progressive,
              lastKnown,
              languageCode: languageCode,
              generation: generation,
            ),
          );
        }

        final coordinates = await progressive.getCurrentCoordinates();
        if (!coordinates.hasValidCoordinates) {
          if (state.status != CurrentLocationStatus.cached) {
            state = state.copyWith(status: CurrentLocationStatus.unavailable);
          }
          return state;
        }
        final resolvedCoordinates = _withCanonicalLocality(
          coordinates,
          candidates: [state.location, existing, persistedLocality?.asLocation],
        );
        state = CurrentLocationState(
          status: CurrentLocationStatus.available,
          localityStatus: _hasLocality(resolvedCoordinates)
              ? CurrentLocalityStatus.cached
              : CurrentLocalityStatus.resolving,
          location: resolvedCoordinates,
        );
        unawaited(
          _resolveLocality(
            progressive,
            coordinates,
            languageCode: languageCode,
            generation: generation,
          ),
        );
        return state;
      }
      final location = await source.getCurrentDeviceLocation(
        languageCode: languageCode,
      );
      if (!location.hasValidCoordinates) {
        state = state.copyWith(status: CurrentLocationStatus.unavailable);
        return state;
      }
      state = CurrentLocationState(
        status: CurrentLocationStatus.available,
        localityStatus: _hasLocality(location)
            ? CurrentLocalityStatus.available
            : CurrentLocalityStatus.unavailable,
        location: location,
      );
      if (_hasLocality(location)) {
        unawaited(_persistLocality(location));
      }
    } on LocationFailure catch (failure) {
      if (state.status != CurrentLocationStatus.cached ||
          failure.reason != LocationFailureReason.unavailable) {
        state = state.copyWith(status: _statusForFailure(failure.reason));
      }
    } on Exception {
      if (state.status != CurrentLocationStatus.cached) {
        state = state.copyWith(status: CurrentLocationStatus.unavailable);
      }
    }
    return state;
  }

  Future<void> _resolveLocality(
    ProgressiveDeviceLocationSource source,
    CurrentDeviceLocation coordinates, {
    required String languageCode,
    required int generation,
  }) async {
    final locality = await source.resolveDeviceLocality(
      coordinates,
      languageCode: languageCode,
    );
    if (generation != _requestGeneration) return;
    final current = state.location;
    if (current == null ||
        current.latitude != coordinates.latitude ||
        current.longitude != coordinates.longitude) {
      return;
    }
    if (locality == null) {
      state = state.copyWith(
        localityStatus: _hasLocality(current)
            ? CurrentLocalityStatus.cached
            : CurrentLocalityStatus.unavailable,
      );
      return;
    }
    final enriched = current.copyWith(
      label: locality.label,
      locality: locality.locality,
      region: locality.region,
      countryCode: locality.countryCode,
    );
    state = CurrentLocationState(
      status: state.status,
      localityStatus: CurrentLocalityStatus.available,
      location: enriched,
    );
    unawaited(_persistLocality(enriched));
  }

  static CurrentDeviceLocation _withCanonicalLocality(
    CurrentDeviceLocation coordinates, {
    required Iterable<CurrentDeviceLocation?> candidates,
  }) {
    if (_hasLocality(coordinates)) return coordinates;
    for (final candidate in candidates) {
      if (candidate == null || !_hasLocality(candidate)) continue;
      if (_distanceKm(coordinates, candidate) >
          _maximumLocalityReuseDistanceKm) {
        continue;
      }
      return coordinates.copyWith(
        label: candidate.label,
        locality: candidate.locality,
        region: candidate.region,
        countryCode: candidate.countryCode,
      );
    }
    return coordinates;
  }

  static bool _hasLocality(CurrentDeviceLocation location) {
    final label = location.label?.trim();
    final locality = location.locality?.trim();
    return (label != null && label.isNotEmpty) ||
        (locality != null && locality.isNotEmpty);
  }

  static double _distanceKm(
    CurrentDeviceLocation first,
    CurrentDeviceLocation second,
  ) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = _radians(second.latitude - first.latitude);
    final longitudeDelta = _radians(second.longitude - first.longitude);
    final firstLatitude = _radians(first.latitude);
    final secondLatitude = _radians(second.latitude);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  Future<_CachedDeviceLocality?> _restoreCachedLocality() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final latitude = preferences.getDouble(_cachedLatitudeKey);
      final longitude = preferences.getDouble(_cachedLongitudeKey);
      final label = preferences.getString(_cachedLabelKey)?.trim();
      final resolvedAtMilliseconds = preferences.getInt(_cachedResolvedAtKey);
      if (latitude == null ||
          longitude == null ||
          label == null ||
          label.isEmpty ||
          resolvedAtMilliseconds == null) {
        return null;
      }
      final resolvedAt = DateTime.fromMillisecondsSinceEpoch(
        resolvedAtMilliseconds,
        isUtc: true,
      );
      final age = DateTime.now().toUtc().difference(resolvedAt);
      if (age.isNegative || age > _maximumCachedLocalityAge) return null;
      return _CachedDeviceLocality(
        latitude: latitude,
        longitude: longitude,
        resolvedAt: resolvedAt,
        locality: DeviceLocality(
          label: label,
          locality: preferences.getString(_cachedLocalityKey),
          region: preferences.getString(_cachedRegionKey),
          countryCode: preferences.getString(_cachedCountryKey),
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _persistLocality(CurrentDeviceLocation location) async {
    final label = location.label?.trim();
    if (label == null || label.isEmpty) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await Future.wait([
        preferences.setDouble(_cachedLatitudeKey, location.latitude),
        preferences.setDouble(_cachedLongitudeKey, location.longitude),
        preferences.setString(_cachedLabelKey, label),
        preferences.setInt(
          _cachedResolvedAtKey,
          DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
        _setOptionalString(preferences, _cachedLocalityKey, location.locality),
        _setOptionalString(preferences, _cachedRegionKey, location.region),
        _setOptionalString(
          preferences,
          _cachedCountryKey,
          location.countryCode,
        ),
      ]);
    } on Object {
      // Locality persistence is a best-effort display cache only.
    }
  }

  static Future<bool> _setOptionalString(
    SharedPreferences preferences,
    String key,
    String? value,
  ) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty
        ? preferences.remove(key)
        : preferences.setString(key, normalized);
  }

  static CurrentLocationStatus _statusForFailure(
    LocationFailureReason reason,
  ) => switch (reason) {
    LocationFailureReason.serviceDisabled =>
      CurrentLocationStatus.serviceDisabled,
    LocationFailureReason.permissionDenied =>
      CurrentLocationStatus.permissionDenied,
    LocationFailureReason.permissionDeniedForever =>
      CurrentLocationStatus.permissionDeniedForever,
    LocationFailureReason.unavailable => CurrentLocationStatus.unavailable,
  };
}

class _CachedDeviceLocality {
  const _CachedDeviceLocality({
    required this.latitude,
    required this.longitude,
    required this.resolvedAt,
    required this.locality,
  });

  final double latitude;
  final double longitude;
  final DateTime resolvedAt;
  final DeviceLocality locality;

  CurrentDeviceLocation get asLocation => CurrentDeviceLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 0,
    observedAt: resolvedAt,
    label: locality.label,
    locality: locality.locality,
    region: locality.region,
    countryCode: locality.countryCode,
  );
}

final currentLocationProvider =
    NotifierProvider<CurrentLocationController, CurrentLocationState>(
      CurrentLocationController.new,
    );

final currentEnvironmentalContextProvider = Provider<EnvironmentalContext?>((
  ref,
) {
  final location = ref.watch(currentLocationProvider).location;
  if (location == null || !location.hasValidCoordinates) return null;
  return EnvironmentalContext(
    source: EnvironmentalContextSource.deviceGps,
    latitude: location.latitude,
    longitude: location.longitude,
    observedAt: location.observedAt,
    displayLabel: location.label,
    locality: location.locality,
    region: location.region,
    countryCode: location.countryCode,
  );
});

class ContentRegionController extends Notifier<ContentRegion?> {
  static const _countryPreferenceKey = 'content_region_country_v1';
  static const _regionPreferenceKey = 'content_region_region_v1';

  ContentRegion? _explicitRegion;
  bool _restoreStarted = false;
  int _selectionGeneration = 0;

  @override
  ContentRegion? build() {
    final physicalLocation = ref.watch(currentLocationProvider).location;

    if (!_restoreStarted) {
      _restoreStarted = true;
      unawaited(_restorePersistedRegion());
    }

    return _explicitRegion ?? _fromPhysicalLocation(physicalLocation);
  }

  Future<void> selectCountry({
    required String countryCode,
    String? region,
    bool persist = true,
  }) async {
    final normalizedCountry = countryCode.trim().toUpperCase();
    if (normalizedCountry.isEmpty) {
      throw ArgumentError.value(
        countryCode,
        'countryCode',
        'Country code cannot be empty.',
      );
    }

    final normalizedRegion = region?.trim();
    final next = ContentRegion(
      countryCode: normalizedCountry,
      region: normalizedRegion == null || normalizedRegion.isEmpty
          ? null
          : normalizedRegion,
      derivedAt: DateTime.now().toUtc(),
      source: ContentRegionSource.explicitSelection,
    );

    _selectionGeneration++;
    _explicitRegion = next;
    state = next;

    if (!persist) return;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_countryPreferenceKey, normalizedCountry);

    if (next.region == null) {
      await preferences.remove(_regionPreferenceKey);
    } else {
      await preferences.setString(_regionPreferenceKey, next.region!);
    }
  }

  Future<void> useDeviceLocation({bool persist = true}) async {
    _selectionGeneration++;
    _explicitRegion = null;
    state = _fromPhysicalLocation(ref.read(currentLocationProvider).location);

    if (!persist) return;

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_countryPreferenceKey);
    await preferences.remove(_regionPreferenceKey);
  }

  Future<void> _restorePersistedRegion() async {
    final generationAtStart = _selectionGeneration;

    try {
      final preferences = await SharedPreferences.getInstance();
      final storedCountry = preferences
          .getString(_countryPreferenceKey)
          ?.trim()
          .toUpperCase();

      if (storedCountry == null || storedCountry.isEmpty) return;
      if (generationAtStart != _selectionGeneration) return;

      final storedRegion = preferences.getString(_regionPreferenceKey)?.trim();

      final restored = ContentRegion(
        countryCode: storedCountry,
        region: storedRegion == null || storedRegion.isEmpty
            ? null
            : storedRegion,
        derivedAt: DateTime.now().toUtc(),
        source: ContentRegionSource.explicitSelection,
      );

      _explicitRegion = restored;
      state = restored;
    } on Object {
      // Persistence failure must never block GPS-derived country context.
    }
  }

  static ContentRegion? _fromPhysicalLocation(CurrentDeviceLocation? location) {
    final countryCode = location?.countryCode?.trim().toUpperCase();

    if (location == null || countryCode == null || countryCode.isEmpty) {
      return null;
    }

    return ContentRegion(
      countryCode: countryCode,
      region: location.region,
      derivedAt: location.observedAt,
      source: ContentRegionSource.deviceGps,
    );
  }
}

final contentRegionProvider =
    NotifierProvider<ContentRegionController, ContentRegion?>(
      ContentRegionController.new,
    );

const double canonicalLocalContentRadiusKm = 100;

final localContentContextProvider = Provider<LocalContentContext?>((ref) {
  final location = ref.watch(currentLocationProvider).location;
  if (location == null || !location.hasValidCoordinates) return null;
  return LocalContentContext(
    latitude: location.latitude,
    longitude: location.longitude,
    radiusKm: canonicalLocalContentRadiusKm,
    observedAt: location.observedAt,
  );
});
