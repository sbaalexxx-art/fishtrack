import 'dart:async';

import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('cold start publishes last-known then reacts to current GPS', () async {
    final now = DateTime.now();
    final source = _ProgressiveLocationSource(
      lastKnown: _location(
        latitude: 51.45,
        longitude: -2.58,
        observedAt: now.subtract(const Duration(minutes: 4)),
      ),
    );
    final container = ProviderContainer(
      overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);

    final statuses = <CurrentLocationStatus>[];
    container.listen(
      currentLocationProvider,
      (_, next) => statuses.add(next.status),
      fireImmediately: true,
    );

    final refresh = container
        .read(currentLocationProvider.notifier)
        .refresh(languageCode: 'en');
    await source.currentRequested.future;

    final startupState = container.read(currentLocationProvider);
    expect(startupState.status, CurrentLocationStatus.cached);
    expect(startupState.hasUsableLocation, isTrue);
    expect(startupState.location?.latitude, 51.45);

    source.current.complete(
      _location(latitude: 51.46, longitude: -2.59, observedAt: now),
    );
    final resolved = await refresh;

    expect(resolved.status, CurrentLocationStatus.available);
    expect(resolved.location?.latitude, 51.46);
    expect(
      statuses,
      containsAllInOrder([
        CurrentLocationStatus.idle,
        CurrentLocationStatus.locating,
        CurrentLocationStatus.cached,
        CurrentLocationStatus.available,
      ]),
    );
  });

  test(
    'temporary current GPS failure preserves valid last-known state',
    () async {
      final source = _ProgressiveLocationSource(
        lastKnown: _location(
          latitude: 51.45,
          longitude: -2.58,
          observedAt: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
      );
      final container = ProviderContainer(
        overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      final refresh = container
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: 'en');
      await source.currentRequested.future;
      source.current.completeError(
        const LocationFailure(LocationFailureReason.unavailable),
      );

      final resolved = await refresh;
      expect(resolved.status, CurrentLocationStatus.cached);
      expect(resolved.hasUsableLocation, isTrue);
      expect(resolved.location?.latitude, 51.45);
    },
  );

  test(
    'current GPS keeps a nearby last-known locality when geocoding fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final source = _ProgressiveLocationSource(
        lastKnown: _location(
          latitude: 51.4544,
          longitude: -2.5878,
          observedAt: now.subtract(const Duration(minutes: 2)),
          label: 'Bristol, England',
          locality: 'Bristol',
          region: 'England',
          countryCode: 'GB',
        ),
        resolvedLocality: null,
      );
      final container = ProviderContainer(
        overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      final refresh = container
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: 'en');
      await source.currentRequested.future;
      source.current.complete(
        _location(latitude: 51.4545, longitude: -2.5879, observedAt: now),
      );
      await refresh;
      await Future<void>.delayed(Duration.zero);

      final resolved = container.read(currentLocationProvider);
      expect(resolved.status, CurrentLocationStatus.available);
      expect(resolved.localityStatus, CurrentLocalityStatus.cached);
      expect(resolved.location?.latitude, 51.4545);
      expect(resolved.location?.label, 'Bristol, England');
    },
  );

  test(
    'cached locality is never reused for distant current coordinates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.now();
      final source = _ProgressiveLocationSource(
        lastKnown: _location(
          latitude: 51.4545,
          longitude: -2.5879,
          observedAt: now.subtract(const Duration(minutes: 2)),
          label: 'Bristol, England',
          locality: 'Bristol',
          region: 'England',
          countryCode: 'GB',
        ),
        resolvedLocality: null,
      );
      final container = ProviderContainer(
        overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      final refresh = container
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: 'en');
      await source.currentRequested.future;
      source.current.complete(
        _location(latitude: 51.5074, longitude: -0.1278, observedAt: now),
      );
      await refresh;
      await Future<void>.delayed(Duration.zero);

      final resolved = container.read(currentLocationProvider);
      expect(resolved.status, CurrentLocationStatus.available);
      expect(resolved.localityStatus, CurrentLocalityStatus.unavailable);
      expect(resolved.location?.label, isNull);
    },
  );

  test(
    'persisted canonical locality survives a temporary geocoder failure',
    () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'current_locality_v1_latitude': 51.4544,
        'current_locality_v1_longitude': -2.5878,
        'current_locality_v1_label': 'Bristol, England',
        'current_locality_v1_locality': 'Bristol',
        'current_locality_v1_region': 'England',
        'current_locality_v1_country': 'GB',
        'current_locality_v1_resolved_at': now
            .subtract(const Duration(hours: 2))
            .toUtc()
            .millisecondsSinceEpoch,
      });
      final source = _ProgressiveLocationSource(
        lastKnown: null,
        resolvedLocality: null,
      );
      final container = ProviderContainer(
        overrides: [deviceLocationSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);

      source.current.complete(
        _location(latitude: 51.4545, longitude: -2.5879, observedAt: now),
      );
      await container
          .read(currentLocationProvider.notifier)
          .refresh(languageCode: 'en');
      await Future<void>.delayed(Duration.zero);

      final resolved = container.read(currentLocationProvider);
      expect(resolved.status, CurrentLocationStatus.available);
      expect(resolved.localityStatus, CurrentLocalityStatus.cached);
      expect(resolved.location?.label, 'Bristol, England');
      expect(resolved.location?.countryCode, 'GB');
    },
  );
}

CurrentDeviceLocation _location({
  required double latitude,
  required double longitude,
  required DateTime observedAt,
  String? label,
  String? locality,
  String? region,
  String? countryCode,
}) => CurrentDeviceLocation(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: 12,
  observedAt: observedAt,
  label: label,
  locality: locality,
  region: region,
  countryCode: countryCode,
);

class _ProgressiveLocationSource
    implements DeviceLocationSource, ProgressiveDeviceLocationSource {
  _ProgressiveLocationSource({
    required this.lastKnown,
    this.resolvedLocality = const DeviceLocality(label: 'Physical place'),
  });

  final CurrentDeviceLocation? lastKnown;
  final DeviceLocality? resolvedLocality;
  final Completer<CurrentDeviceLocation> current = Completer();
  final Completer<void> currentRequested = Completer();

  @override
  Future<CurrentDeviceLocation?> getLastKnownCoordinates() async => lastKnown;

  @override
  Future<CurrentDeviceLocation> getCurrentCoordinates() {
    if (!currentRequested.isCompleted) currentRequested.complete();
    return current.future;
  }

  @override
  Future<CurrentDeviceLocation> getCurrentDeviceLocation({
    required String languageCode,
  }) => current.future;

  @override
  Future<DeviceLocality?> resolveDeviceLocality(
    CurrentDeviceLocation location, {
    required String languageCode,
  }) async => resolvedLocality;
}
