import 'package:fishtrack/core/context/selected_context.dart';
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
}
