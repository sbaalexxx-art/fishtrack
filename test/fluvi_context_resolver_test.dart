import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ukGps = CurrentDeviceLocation(
    latitude: 51.4545,
    longitude: -2.5879,
    accuracyMeters: 8,
    observedAt: DateTime.now(),
    label: 'Bristol',
    locality: 'Bristol',
    countryCode: 'GB',
  );

  test('GPS UK is canonical when there is no explicit selection', () {
    final resolved = resolveFluviContext(
      selected: null,
      physicalLocation: ukGps,
    );

    expect(resolved?.source, FluviResolvedContextSource.physicalGps);
    expect(resolved?.primaryLabel, 'Bristol');
    expect(resolved?.countryCode, 'GB');
    expect(resolved?.latitude, ukGps.latitude);
    expect(resolved?.longitude, ukGps.longitude);
  });

  test('Olt without coordinates preserves identity and remains unknown', () {
    const olt = SelectedContext(
      countryCode: 'RO',
      locationName: 'Olt',
      waterId: 'river-olt',
      waterName: 'Olt',
      riverName: 'Olt',
      riverKey: 'olt',
      source: 'Water catalog',
    );

    final resolved = resolveFluviContext(
      selected: olt,
      physicalLocation: ukGps,
    );

    expect(resolved?.source, FluviResolvedContextSource.selectedEntity);
    expect(resolved?.entityType, 'river');
    expect(resolved?.entityId, 'olt');
    expect(resolved?.primaryLabel, 'Olt');
    expect(resolved?.hasUsableCoordinates, isFalse);
    expect(resolved?.environmentalContext, isNull);
  });

  test('Frunzaru with coordinates wins over UK GPS', () {
    const frunzaru = SelectedContext(
      countryCode: 'RO',
      locationName: 'Frunzaru',
      latitude: 44.333,
      longitude: 24.617,
      hydropowerPlantId: 'frunzaru',
      source: 'Hydro canonical entity',
    );

    final resolved = resolveFluviContext(
      selected: frunzaru,
      physicalLocation: ukGps,
    );

    expect(resolved?.entityId, 'frunzaru');
    expect(resolved?.primaryLabel, 'Frunzaru');
    expect(resolved?.latitude, 44.333);
    expect(resolved?.longitude, 24.617);
    expect(resolved?.countryCode, 'RO');
    expect(resolved?.contextKey, contains('frunzaru'));
  });

  test('explicit selected location wins without mutating physical GPS', () {
    const selected = SelectedContext(
      countryCode: 'RO',
      locationName: 'Selected place',
      latitude: 45.1,
      longitude: 24.1,
      placeId: 'selected-place',
    );

    final resolved = resolveFluviContext(
      selected: selected,
      physicalLocation: ukGps,
    );

    expect(resolved?.entityId, 'selected-place');
    expect(resolved?.latitude, 45.1);
    expect(ukGps.latitude, 51.4545);
    expect(ukGps.longitude, -2.5879);
  });

  test('automatic station publication does not replace physical GPS', () {
    const automatic = SelectedContext(
      stationId: 'old-danube',
      stationName: 'Old Danube',
      latitude: 44.0,
      longitude: 22.0,
      origin: SelectedContextOrigin.automaticStation,
    );

    final resolved = resolveFluviContext(
      selected: automatic,
      physicalLocation: ukGps,
    );

    expect(resolved?.source, FluviResolvedContextSource.physicalGps);
    expect(resolved?.primaryLabel, 'Bristol');
    expect(resolved?.stationId, isNull);
  });
}
