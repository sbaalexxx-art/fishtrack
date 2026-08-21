import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B45C Hydro Map regression contract', () {
    final mapSource = File('lib/screens/map_page.dart').readAsStringSync();
    final panelSource = File(
      'lib/widgets/fluviai/hydro_intelligence_panel.dart',
    ).readAsStringSync();

    test('keeps the approved Danube station runtime intact', () {
      expect(mapSource, contains('_stationAnnotationManager'));
      expect(mapSource, contains('Future<void> _loadStations()'));
      expect(mapSource, contains('_syncStationAnnotations()'));
      expect(mapSource, contains('_stationAnnotationOptions('));
      expect(mapSource, contains("'type': 'water_station'"));
    });

    test(
      'uses canonical verified Hydro sites instead of generic Hydro pins',
      () {
        expect(mapSource, contains('HydroMapCanonicalService'));
        expect(
          mapSource,
          contains('_hydroMapCanonicalService.getVerifiedSites'),
        );
        expect(mapSource, isNot(contains('.where((pin) => pin.isHydropower)')));
        expect(mapSource, contains('canonicalDamIds.contains(asset.id)'));
        expect(mapSource, contains('canonicalReservoirIds.contains(asset.id)'));
        expect(mapSource, contains("payload['dam_id']"));
        expect(mapSource, contains("payload['reservoir_id']"));
      },
    );

    test('Hydro map preview never requests or renders installed MW', () {
      expect(
        mapSource,
        isNot(contains('getHydropowerPlantState(\n        pin.entityId')),
      );
      expect(mapSource, isNot(contains("'Putere instalată'")));
      expect(mapSource, isNot(contains("'Installed capacity'")));
    });

    test('forecast is an explicit separate block in the existing panel', () {
      expect(panelSource, contains('forecastProbabilityLabel'));
      expect(panelSource, contains('forecastWindowLabel'));
      expect(panelSource, contains('hydro-panel-dispatch-summary'));
      expect(panelSource, contains('PROBABILITATE DE UZINARE'));
      expect(panelSource, contains('Interval estimat'));
    });
  });
}
