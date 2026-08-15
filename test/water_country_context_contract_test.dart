import 'package:fishtrack/core/context/current_location.dart';
import 'package:fishtrack/core/context/environmental_context.dart';
import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/models/water_asset.dart';
import 'package:fishtrack/models/water_river.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  test('water asset preserves backend country code', () {
    final asset = WaterAssetRef.fromJson(const <String, dynamic>{
      'asset_type': 'dam',
      'entity_id': 'vidraru',
      'name': 'Vidraru',
      'country_code': 'ro',
      'latitude': 45.36,
      'longitude': 24.63,
    });

    expect(asset.countryCode, 'RO');
  });

  test('map pin propagates backend country to WaterAssetRef', () {
    final pin = WaterMapPin.fromJson(const <String, dynamic>{
      'entity_type': 'reservoir',
      'entity_id': 'vidraru-reservoir',
      'canonical_key': 'reservoir:vidraru',
      'name': 'Vidraru',
      'country_code': 'ro',
      'latitude': 45.36,
      'longitude': 24.63,
      'state_payload': <String, Object?>{},
    });

    expect(pin.countryCode, 'RO');
    expect(pin.toWaterAssetRef()?.countryCode, 'RO');
  });

  test('hydropower state preserves backend country code', () {
    final state = HydropowerPlantState.fromJson(const <String, dynamic>{
      'plant_id': 'plant-1',
      'canonical_key': 'hydro:plant-1',
      'name': 'CHE Test',
      'country_code': 'ro',
      'operation_state': 'UNKNOWN',
      'evidence_class': 'UNKNOWN',
      'evidence_source': 'unavailable',
      'confidence': 0,
      'freshness_status': 'unavailable',
    });

    expect(state.countryCode, 'RO');
  });

  test('river identity never invents Romania when country is absent', () {
    final river = WaterRiverRef.fromJson(const <String, dynamic>{
      'river_key': 'test',
      'name': 'Test River',
      'dam_count': 0,
      'reservoir_count': 0,
      'basin_names': <String>[],
      'counties': <String>[],
    });

    expect(river.countryCode, isEmpty);
  });

  test(
    'explicit selected entity updates ContentRegion, not physical GPS',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(currentLocationProvider).location, isNull);

      container
          .read(selectedContextProvider.notifier)
          .select(
            const SelectedContext(
              countryCode: 'ro',
              waterId: 'water-1',
              waterName: 'Vidraru',
            ),
          );

      await Future<void>.delayed(Duration.zero);

      final region = container.read(contentRegionProvider);

      expect(region?.countryCode, 'RO');
      expect(region?.source, ContentRegionSource.explicitSelection);
      expect(container.read(currentLocationProvider).location, isNull);
    },
  );
}
