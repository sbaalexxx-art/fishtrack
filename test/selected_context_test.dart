import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/models/station.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });
  test(
    'SelectedContext starts empty and preserves a real selection contract',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(selectedContextProvider), isNull);
      container
          .read(selectedContextProvider.notifier)
          .select(
            const SelectedContext(
              countryCode: 'RO',
              region: 'test-region',
              locationName: 'test-location',
              latitude: 45,
              longitude: 25,
              waterId: 'water-1',
              riverName: 'test-river',
              stationId: 'station-1',
              stationName: 'test-station',
              source: 'test-source',
            ),
          );

      final selected = container.read(selectedContextProvider)!;
      expect(selected.hasCoordinates, isTrue);
      expect(selected.hasEntity, isTrue);
      expect(selected.primaryLabel, 'test-station');
      expect(selected.selectedAt, isNotNull);

      container.read(selectedContextProvider.notifier).clear();
      expect(container.read(selectedContextProvider), isNull);
    },
  );

  test('access tier defaults to Free and can represent Premium', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(fluviAccessTierProvider), FluviAccessTier.free);
    container
        .read(fluviAccessTierProvider.notifier)
        .setTier(FluviAccessTier.premium);
    expect(container.read(fluviAccessTierProvider), FluviAccessTier.premium);
  });

  test('fromStation propagates canonical country without fabricating it', () {
    final known = SelectedContext.fromStation(_station(countryCode: 'ro'));
    final unknown = SelectedContext.fromStation(_station());

    expect(known.countryCode, 'ro');
    expect(known.origin, SelectedContextOrigin.selectedStation);
    expect(unknown.countryCode, isNull);
  });

  test('automatic no-match does not clear an explicit selection', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(selectedContextProvider.notifier);

    controller.publishAutomaticStation(_station(id: 'auto'));
    expect(
      container.read(selectedContextProvider)?.origin,
      SelectedContextOrigin.automaticStation,
    );
    controller.clearAutomaticStation();
    expect(container.read(selectedContextProvider), isNull);

    controller.publishStation(_station(id: 'explicit'));
    controller.clearAutomaticStation();
    expect(container.read(selectedContextProvider)?.stationId, 'explicit');
  });
}

Station _station({String id = 'station', String? countryCode}) => Station(
  id: id,
  name: 'Station',
  river: 'River',
  countryCode: countryCode,
  level: 100,
  trend: WaterTrend.stable,
  latitude: 45,
  longitude: 25,
  lastUpdate: DateTime.now(),
  hasWaterLevel: true,
);
