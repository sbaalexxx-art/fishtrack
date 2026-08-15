import 'dart:async';

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

class CurrentLocationState {
  const CurrentLocationState({
    this.status = CurrentLocationStatus.idle,
    this.location,
  });

  final CurrentLocationStatus status;
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
    CurrentDeviceLocation? location,
  }) => CurrentLocationState(
    status: status ?? this.status,
    location: location ?? this.location,
  );
}

final deviceLocationSourceProvider = Provider<DeviceLocationSource>(
  (_) => const LocationService(),
);

class CurrentLocationController extends Notifier<CurrentLocationState> {
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
    state = state.copyWith(status: CurrentLocationStatus.locating);
    try {
      final source = ref.read(deviceLocationSourceProvider);
      if (source is ProgressiveDeviceLocationSource) {
        final progressive = source as ProgressiveDeviceLocationSource;
        final lastKnown = await progressive.getLastKnownCoordinates();
        if (lastKnown?.isValidLastKnownAt(DateTime.now()) == true) {
          state = CurrentLocationState(
            status: CurrentLocationStatus.cached,
            location: lastKnown,
          );
          unawaited(
            _resolveLocality(
              progressive,
              lastKnown!,
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
        state = CurrentLocationState(
          status: CurrentLocationStatus.available,
          location: coordinates,
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
        location: location,
      );
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
    if (locality == null || generation != _requestGeneration) return;
    final current = state.location;
    if (current == null ||
        current.latitude != coordinates.latitude ||
        current.longitude != coordinates.longitude) {
      return;
    }
    state = CurrentLocationState(
      status: state.status,
      location: current.copyWith(
        label: locality.label,
        locality: locality.locality,
        region: locality.region,
        countryCode: locality.countryCode,
      ),
    );
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
