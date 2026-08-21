import 'package:fishtrack/services/hydro_map_canonical_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hydro canonical mobile contract', () {
    test('verified site becomes exactly one hydro pin anchored to the dam', () {
      final site = HydroCanonicalMapSite.fromJson(<String, dynamic>{
        'site_key': 'baraj:dam-1',
        'pin_eligible': true,
        'display_name': 'Draganesti · Olt',
        'river_name': 'Olt',
        'country_code': 'RO',
        'basin_name': 'A.B.A. Olt',
        'latitude': 44.1638118,
        'longitude': 24.4823982,
        'anchor_type': 'hydro_verified_dam_anchor',
        'hydropower_verified': true,
        'dispatch_available': true,
        'plant_id': 'plant-1',
        'dam_id': 'dam-1',
        'reservoir_id': 'reservoir-1',
        'water_body_id': 'water-1',
      });

      expect(site.isVerifiedPin, isTrue);
      final pin = site.toWaterMapPin();
      expect(pin.isHydropower, isTrue);
      expect(pin.entityId, 'plant-1');
      expect(pin.canonicalKey, 'baraj:dam-1');
      expect(pin.latitude, 44.1638118);
      expect(pin.longitude, 24.4823982);
      expect(pin.operationState, 'UNKNOWN');
      expect(pin.evidenceClass, 'UNKNOWN');
      expect(pin.hasOperationalData, isFalse);
      expect(pin.statePayload['dam_id'], 'dam-1');
      expect(pin.statePayload['reservoir_id'], 'reservoir-1');
      expect(pin.statePayload['dispatch_available'], isTrue);
    });

    test(
      'unverified hydropower-use site cannot masquerade as a hydro plant pin',
      () {
        final site = HydroCanonicalMapSite.fromJson(<String, dynamic>{
          'site_key': 'baraj:dam-2',
          'pin_eligible': true,
          'display_name': 'Unverified site',
          'latitude': 45.0,
          'longitude': 25.0,
          'anchor_type': 'dam_anchor',
          'hydropower_verified': false,
          'dispatch_available': false,
          'dam_id': 'dam-2',
          'reservoir_id': 'reservoir-2',
        });

        expect(site.isVerifiedPin, isFalse);
      },
    );

    test('dispatch snapshot keeps forecast separate from observed truth', () {
      final snapshot = HydroMapDispatchSnapshot.fromJson(<String, dynamic>{
        'plant_id': 'plant-1',
        'dam_id': 'dam-1',
        'reservoir_id': 'reservoir-1',
        'name': 'Draganesti',
        'availability_status': 'AVAILABLE',
        'window_start': '2026-08-21T13:30:00Z',
        'window_end': '2026-08-21T20:00:00Z',
        'window_probability': 0.6834,
        'peak_probability': 0.72,
        'confidence': 'low',
        'evidence_class': 'ESTIMATED',
        'updated_at': '2026-08-20T14:58:46Z',
        'observed_state': 'NO_RECENT_OBSERVATION',
        'observed_confidence': 0,
        'observed_freshness': 'unavailable',
        'observed_report_count': 0,
      });

      expect(snapshot.isAvailable, isTrue);
      expect(snapshot.windowProbability, closeTo(0.6834, 0.00001));
      expect(snapshot.evidenceClass, 'ESTIMATED');
      expect(snapshot.observedState, 'NO_RECENT_OBSERVATION');
      expect(snapshot.observedReportCount, 0);
    });
  });
}
