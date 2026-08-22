import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('station A to B produces a new deterministic context key', () {
    final a = resolveFluviContext(
      selected: SelectedContext.fromStation(_station('a', 'Station A', 44, 22)),
      physicalLocation: null,
    )!;
    final b = resolveFluviContext(
      selected: SelectedContext.fromStation(_station('b', 'Station B', 45, 23)),
      physicalLocation: null,
    )!;

    expect(a.contextKey, isNot(b.contextKey));
    expect(a.stationId, 'a');
    expect(b.stationId, 'b');
  });

  test('Map B isolates context from Water preference A', () {
    final water = WaterService();
    water.selectStation(_station('a', 'Station A', 44, 22));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(selectedContextProvider.notifier)
        .publishStation(_station('b', 'Station B', 45, 23));

    expect(water.selectedStation?.id, 'a');
    expect(container.read(canonicalFluviContextProvider)?.stationId, 'b');
  });

  test(
    'UK GPS to selected RO entity changes identity and coordinates atomically',
    () {
      final uk = CurrentDeviceLocation(
        latitude: 51.4545,
        longitude: -2.5879,
        accuracyMeters: 8,
        observedAt: DateTime.now(),
        countryCode: 'GB',
      );
      final gps = resolveFluviContext(selected: null, physicalLocation: uk)!;
      final ro = resolveFluviContext(
        selected: const SelectedContext(
          countryCode: 'RO',
          locationName: 'Frunzaru',
          latitude: 44.333,
          longitude: 24.617,
          hydropowerPlantId: 'frunzaru',
        ),
        physicalLocation: uk,
      )!;

      expect(gps.countryCode, 'GB');
      expect(ro.countryCode, 'RO');
      expect(ro.entityId, 'frunzaru');
      expect(ro.contextKey, isNot(gps.contextKey));
    },
  );

  test('automatic no-match clears only previous automatic context', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(selectedContextProvider.notifier);

    notifier.publishAutomaticStation(_station('auto', 'Automatic', 44, 22));
    expect(container.read(selectedContextProvider)?.stationId, 'auto');
    notifier.clearAutomaticStation();
    expect(container.read(selectedContextProvider), isNull);

    notifier.publishStation(_station('explicit', 'Explicit', 45, 23));
    notifier.clearAutomaticStation();
    expect(container.read(selectedContextProvider)?.stationId, 'explicit');
  });
}

Station _station(String id, String name, double latitude, double longitude) =>
    Station(
      id: id,
      name: name,
      river: 'Dunărea',
      countryCode: 'RO',
      level: 100,
      trend: WaterTrend.stable,
      latitude: latitude,
      longitude: longitude,
      lastUpdate: DateTime.now(),
      hasWaterLevel: true,
    );
