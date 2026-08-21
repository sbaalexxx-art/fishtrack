import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RC2.2C-1D Hydro identity/icon semantics', () {
    test('raw public dam diamonds are presentation-disabled', () {
      final overlay = File(
        'lib/core/map/hydro_ro_vector_overlay.dart',
      ).readAsStringSync();

      expect(
        overlay,
        contains(
          'symbols are rendered only from canonical runtime WaterAsset annotations',
        ),
      );
      expect(overlay, isNot(contains("textField: '◆'")));
      expect(overlay, isNot(contains('if (preferences.dams) damLayerId')));
      expect(
        overlay,
        isNot(contains('if (preferences.dams) damSelectedLayerId')),
      );
    });

    test(
      'reservoir geometry resolves to canonical identity with nearby fallback',
      () {
        final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

        expect(mapPage, contains('final searchCandidates ='));
        expect(mapPage, contains('final nearbyCandidates ='));
        expect(mapPage, contains('_bestNearbyAssetMatch('));
        expect(mapPage, contains('_normalizeHydroIdentityName('));
        expect(
          mapPage,
          contains(
            'all panel/context identity comes from the canonical Supabase asset',
          ),
        );
      },
    );

    test('dam icons are canonical runtime annotations only at local zoom', () {
      final mapPage = File('lib/screens/map_page.dart').readAsStringSync();

      expect(mapPage, contains('final localCanonicalReservoir ='));
      expect(
        mapPage,
        contains(
          'asset.type == WaterAssetType.reservoir && _cameraZoom >= 10.2',
        ),
      );
      expect(mapPage, contains('final localCanonicalDam ='));
      expect(
        mapPage,
        contains('asset.type == WaterAssetType.dam && _cameraZoom >= 11.6'),
      );
      expect(mapPage, contains('localCanonicalReservoir'));
      expect(mapPage, contains('localCanonicalDam'));
      expect(mapPage, contains('densityKeys.contains(key)'));
    });
  });
}
