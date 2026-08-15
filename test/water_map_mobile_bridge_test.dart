import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/models/water_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Water Map Mobile Bridge', () {
    test('parses canonical hydropower map pin without inventing evidence', () {
      final pin = WaterMapPin.fromJson(<String, dynamic>{
        'entity_type': 'hydro_plant',
        'entity_id': 'plant-1',
        'canonical_key': 'ro:hydro-plant:olt-test',
        'name': 'CHE Test',
        'river_name': 'Olt',
        'latitude': 45.5,
        'longitude': 24.5,
        'water_body_id': 'water-1',
        'distance_km': 4.2,
        'trend_state': 'unknown',
        'operation_state': 'UNKNOWN',
        'evidence_class': 'UNKNOWN',
        'state_source': 'unavailable',
        'confidence': 0,
        'freshness_status': 'unavailable',
        'priority': 93,
        'has_operational_data': false,
        'community_report_count': 0,
        'state_payload': <String, Object?>{
          'operator_name': 'Operator test',
        },
      });

      expect(pin.isHydropower, isTrue);
      expect(pin.canonicalKey, 'ro:hydro-plant:olt-test');
      expect(pin.operationState, 'UNKNOWN');
      expect(pin.evidenceClass, 'UNKNOWN');
      expect(pin.confidence, 0);
      expect(pin.hasOperationalData, isFalse);
      expect(pin.toWaterAssetRef(), isNull);
    });

    test('converts dam map pin to existing WaterAssetRef contract', () {
      final pin = WaterMapPin.fromJson(<String, dynamic>{
        'entity_type': 'dam',
        'entity_id': 'dam-vidraru',
        'canonical_key': 'dam:dam-vidraru',
        'name': 'Vidraru',
        'river_name': 'Arges',
        'latitude': 45.3665999,
        'longitude': 24.6310505,
        'water_body_id': 'water-arges',
        'trend_state': 'unknown',
        'operation_state': 'UNKNOWN',
        'evidence_class': 'UNKNOWN',
        'state_source': 'unavailable',
        'confidence': 0,
        'freshness_status': 'unavailable',
        'priority': 94,
        'has_operational_data': false,
        'community_report_count': 0,
        'state_payload': <String, Object?>{
          'subtitle': 'A · ARGES · A.B.A. Argeș-Vedea',
          'county': 'ARGES',
          'basin_name': 'A.B.A. Argeș-Vedea',
        },
      });

      final asset = pin.toWaterAssetRef();
      expect(asset, isNotNull);
      expect(asset!.type, WaterAssetType.dam);
      expect(asset.id, 'dam-vidraru');
      expect(asset.name, 'Vidraru');
      expect(asset.waterBodyId, 'water-arges');
      expect(asset.county, 'ARGES');
      expect(asset.basinName, 'A.B.A. Argeș-Vedea');
      expect(asset.stateSource, 'unavailable');
      expect(asset.stateConfidence, 0);
      expect(asset.hasOperationalData, isFalse);
    });

    test('hydropower UNKNOWN state keeps all operational values unavailable', () {
      final state = HydropowerPlantState.fromJson(<String, dynamic>{
        'plant_id': 'plant-1',
        'canonical_key': 'ro:hydro-plant:olt-test',
        'name': 'CHE Test',
        'operator_name': 'Hidroelectrica S.A.',
        'water_body_id': 'water-1',
        'dam_id': 'dam-1',
        'reservoir_id': 'reservoir-1',
        'latitude': 45.5,
        'longitude': 24.5,
        'operation_state': 'UNKNOWN',
        'evidence_class': 'UNKNOWN',
        'evidence_source': 'unavailable',
        'evidence_metric': null,
        'evidence_value': null,
        'evidence_unit': null,
        'evidence_observed_at': null,
        'confidence': 0,
        'freshness_status': 'unavailable',
        'community_operation_signal': 'unknown',
        'community_report_count': 0,
      });

      expect(state.operationState, 'UNKNOWN');
      expect(state.evidenceClass, 'UNKNOWN');
      expect(state.evidenceMetric, isNull);
      expect(state.evidenceValue, isNull);
      expect(state.evidenceUnit, isNull);
      expect(state.evidenceObservedAt, isNull);
      expect(state.confidence, 0);
    });

    test('SelectedContext carries hydropower identity without losing water context', () {
      const selected = SelectedContext(
        countryCode: 'RO',
        locationName: 'CHE Test',
        latitude: 45.5,
        longitude: 24.5,
        waterId: 'water-1',
        waterName: 'Olt',
        riverName: 'Olt',
        hydropowerPlantId: 'plant-1',
        source: 'unavailable',
      );

      expect(selected.hasEntity, isTrue);
      expect(selected.hydropowerPlantId, 'plant-1');
      expect(selected.waterId, 'water-1');

      final refreshed = selected.copyWith(
        damId: 'dam-1',
        reservoirId: 'reservoir-1',
        source: 'official_measured',
      );
      expect(refreshed.hydropowerPlantId, 'plant-1');
      expect(refreshed.waterId, 'water-1');
      expect(refreshed.damId, 'dam-1');
      expect(refreshed.reservoirId, 'reservoir-1');
      expect(refreshed.source, 'official_measured');
    });
  });
}
