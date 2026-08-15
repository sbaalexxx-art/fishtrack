import 'dart:async';

import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

CurrentDeviceLocation _location({
  required double latitude,
  required double longitude,
  required DateTime observedAt,
}) => CurrentDeviceLocation(
  latitude: latitude,
  longitude: longitude,
  accuracyMeters: 12,
  observedAt: observedAt,
);

class _ProgressiveLocationSource
    implements DeviceLocationSource, ProgressiveDeviceLocationSource {
  _ProgressiveLocationSource({required this.lastKnown});

  final CurrentDeviceLocation? lastKnown;
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
  }) async => const DeviceLocality(label: 'Physical place');
}
