import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_misc_pages.dart';
import 'package:fishtrack/models/water_asset.dart';
import 'package:fishtrack/models/water_river.dart';
import 'package:fishtrack/services/water_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const guraLotruluiState = HydropowerPlantState(
    plantId: '0e23fe95-2d25-40a8-82dd-badc006bb061',
    canonicalKey: 'ro:hydro-plant:olt-gura-lotrului',
    name: 'Gura Lotrului',
    countryCode: 'RO',
    operatorName: 'Hidroelectrica S.A.',
    operatorUnit: 'SH Ramnicu Valcea',
    sectorName: 'Olt mijlociu',
    plantKind: 'hydroelectric_power_plant',
    waterBodyId: 'cb7813d3-4a37-427a-ad0c-953f1f07f3f5',
    damId: '14efc6ef-ce2c-434a-88e3-2ff2e511b4d9',
    reservoirId: '6d672eac-88c8-4229-8a9e-b7a3309ca047',
    latitude: 45.3452741,
    longitude: 24.2753023,
    operationState: 'UNKNOWN',
    evidenceClass: 'UNKNOWN',
    evidenceSource: 'unavailable',
    confidence: 0,
    freshnessStatus: 'unavailable',
  );

  test('Search resolves the real canonical Gura Lotrului CHE', () async {
    final service = _CanonicalHydropowerSearchService(guraLotruluiState);

    final results = await service.searchHydropower('Gura Lotrului');

    expect(results, hasLength(1));
    final plant = results.single;
    expect(plant.entityId, guraLotruluiState.plantId);
    expect(plant.canonicalKey, guraLotruluiState.canonicalKey);
    expect(plant.name, 'Gura Lotrului');
    expect(plant.riverName, 'Olt');
    expect(plant.waterBodyId, guraLotruluiState.waterBodyId);
    expect(plant.latitude, 45.3452741);
    expect(plant.longitude, 24.2753023);
    expect(plant.operationState, 'UNKNOWN');
    expect(service.requestedWaterBodyId, guraLotruluiState.waterBodyId);
    expect(service.requestedPlantId, isNull);
  });

  test(
    'real CHE carries MapFocus and SelectedContext without losing identity',
    () {
      final plant = waterMapPinFromHydropowerState(
        guraLotruluiState,
        riverName: 'Olt',
      );
      final entry = hydropowerSearchMapEntry(plant);
      final target = entry.cameraTarget!;
      final selected = SelectedContext.fromHydropowerPin(plant);

      expect(entry.source, 'global-search-hydropower');
      expect(target.source, 'global-search-hydropower');
      expect(target.entityId, guraLotruluiState.plantId);
      expect(target.latitude, 45.3452741);
      expect(target.longitude, 24.2753023);
      expect(target.zoom, 13.4);
      expect(selected.hydropowerPlantId, guraLotruluiState.plantId);
      expect(selected.locationName, 'Gura Lotrului');
      expect(selected.waterId, guraLotruluiState.waterBodyId);
      expect(selected.waterName, 'Olt');
      expect(selected.riverName, 'Olt');
      expect(selected.countryCode, 'RO');
    },
  );
}

class _CanonicalHydropowerSearchService extends WaterAssetService {
  _CanonicalHydropowerSearchService(this.state);

  final HydropowerPlantState state;
  String? requestedWaterBodyId;
  String? requestedPlantId;

  @override
  Future<List<HydropowerPlantState>> getHydropowerPlantStates({
    String? waterBodyId,
    String? plantId,
  }) async {
    requestedWaterBodyId = waterBodyId;
    requestedPlantId = plantId;
    return <HydropowerPlantState>[state];
  }

  @override
  Future<List<WaterRiverRef>> searchRivers(
    String query, {
    int limit = 50,
  }) async => const <WaterRiverRef>[];

  @override
  Future<List<WaterAssetRef>> searchAssets(
    String query, {
    int limit = 50,
  }) async => <WaterAssetRef>[
    WaterAssetRef(
      type: WaterAssetType.dam,
      id: '14efc6ef-ce2c-434a-88e3-2ff2e511b4d9',
      name: 'Gura Lotrului',
      riverName: 'Olt',
      countryCode: 'RO',
      latitude: 45.3452741,
      longitude: 24.2753023,
      waterBodyId: state.waterBodyId,
    ),
  ];
}
