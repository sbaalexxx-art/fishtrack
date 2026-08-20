import 'package:fishtrack/features/hydro_dispatch/presentation/hydro_dispatch_presentation.dart';
import 'package:fishtrack/services/hydro_dispatch_geofence_service.dart';
import 'package:fishtrack/services/hydro_dispatch_service.dart';
import 'package:fishtrack/services/saved_items_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hydro Dispatch P4 mobile contract', () {
    test('today/tomorrow row preserves probability truth metadata', () {
      final row = HydroDispatchDayForecast.fromJson(<String, dynamic>{
        'node_order': 13,
        'plant_id': '11111111-1111-1111-1111-111111111111',
        'plant_name': 'Frunzaru',
        'delivery_date': '2026-08-20',
        'day_offset': 0,
        'availability_status': 'AVAILABLE',
        'window_start': '2026-08-20T15:15:00Z',
        'window_end': '2026-08-20T20:45:00Z',
        'window_probability': 0.6645,
        'peak_probability': 0.7487,
        'confidence': 'low',
        'evidence_class': 'ESTIMATED',
        'model_version': '1.1.0-entsoe-market-only',
        'updated_at': '2026-08-20T10:30:00Z',
        'system_signal_status': 'fresh',
        'hydro_trend': 'falling',
        'corroboration_status': 'partial',
        'local_hydrology_status': 'available',
        'local_rain_signal': 'dry',
        'local_target_count': 5,
      });

      expect(row.plantName, 'Frunzaru');
      expect(row.dayOffset, 0);
      expect(row.isAvailable, isTrue);
      expect(row.windowProbability, closeTo(0.6645, 0.000001));
      expect(row.peakProbability, closeTo(0.7487, 0.000001));
      expect(row.evidenceClass, 'ESTIMATED');
      expect(row.confidence, 'low');
      expect(row.hydroTrend, 'falling');
      expect(row.localRainSignal, 'dry');
    });

    test('presentation uses Romania time even for UTC forecast timestamps', () {
      final row = HydroDispatchDayForecast.fromJson(<String, dynamic>{
        'node_order': 13,
        'plant_id': '11111111-1111-1111-1111-111111111111',
        'plant_name': 'Frunzaru',
        'delivery_date': '2026-08-20',
        'day_offset': 0,
        'availability_status': 'AVAILABLE',
        'window_start': '2026-08-20T15:15:00Z',
        'window_end': '2026-08-20T20:45:00Z',
        'window_probability': 0.6645,
        'peak_probability': 0.7487,
        'confidence': 'low',
        'evidence_class': 'ESTIMATED',
        'system_signal_status': 'fresh',
        'hydro_trend': 'falling',
        'corroboration_status': 'partial',
        'local_hydrology_status': 'available',
        'local_rain_signal': 'dry',
        'local_target_count': 5,
      });

      final presentation = HydroDispatchPresentation.day(row, isRomanian: true);
      expect(presentation.probabilityLabel, '66.5%');
      expect(presentation.windowLabel, '18:15–23:45');
      expect(presentation.evidenceLabel, 'ESTIMATED');
    });

    test(
      'tomorrow not-yet-published never looks available or zero percent',
      () {
        final row = HydroDispatchDayForecast.fromJson(<String, dynamic>{
          'node_order': 13,
          'plant_id': '11111111-1111-1111-1111-111111111111',
          'plant_name': 'Frunzaru',
          'delivery_date': '2026-08-21',
          'day_offset': 1,
          'availability_status': 'NOT_YET_PUBLISHED',
          'confidence': 'unknown',
          'evidence_class': 'UNKNOWN',
          'system_signal_status': 'not_applied_future_day',
          'hydro_trend': 'not_applied_future_day',
          'corroboration_status': 'not_applied_future_day',
          'local_hydrology_status': 'not_applied_future_day',
          'local_rain_signal': 'not_applied_future_day',
          'local_target_count': 0,
        });

        expect(row.isTomorrow, isTrue);
        expect(row.isAvailable, isFalse);
        expect(row.windowProbability, isNull);
        expect(row.peakProbability, isNull);

        final presentation = HydroDispatchPresentation.day(
          row,
          isRomanian: true,
        );
        expect(presentation.available, isFalse);
        expect(presentation.probabilityLabel, '—');
        expect(presentation.statusLabel, 'Încă nepublicat');
      },
    );

    test('AI context keeps observed and estimated evidence distinct', () {
      final context = HydroDispatchAiContext.fromJson(<String, dynamic>{
        'plant_id': '11111111-1111-1111-1111-111111111111',
        'plant_name': 'Frunzaru',
        'day_offset': 0,
        'availability_status': 'AVAILABLE',
        'probability': 0.66,
        'peak_probability': 0.75,
        'probability_band': 'moderate',
        'confidence': 'low',
        'evidence_class': 'ESTIMATED',
        'system_signal_status': 'fresh',
        'hydro_trend': 'falling',
        'local_hydrology_status': 'available',
        'local_rain_signal': 'dry',
        'observed_state': 'OBSERVED_ACTIVE',
        'observed_confidence': 0.9,
        'observed_freshness_status': 'fresh',
        'calibration_status': 'uncalibrated',
        'calibration_sample_count': 0,
        'truth_disclaimer': 'Probability is not confirmed generation.',
      });

      expect(context.evidenceClass, 'ESTIMATED');
      expect(context.observedState, 'OBSERVED_ACTIVE');
      expect(context.observedConfidence, closeTo(0.9, 0.000001));
      expect(context.calibrationSampleCount, 0);
      expect(
        HydroDispatchPresentation.observedLabel(context, isRomanian: true),
        'UZINARE OBSERVATĂ ÎN TEREN',
      );
      final explanation = HydroDispatchPresentation.aiExplanation(
        context,
        isRomanian: true,
      );
      expect(explanation, contains('Probabilitate 66.0%'));
      expect(explanation, contains('nu reprezintă confirmare oficială'));
      expect(explanation, isNot(contains('MW')));
    });

    test('recovered hydropower alias maps to canonical saved-item type', () {
      expect(
        SavedItemsService.canonicalItemType('hydropower'),
        HydroDispatchService.canonicalSavedItemType,
      );
      expect(
        SavedItemsService.canonicalItemType('hydropower_plant'),
        'hydropower_plant',
      );
    });

    test('alert RPC response parses canonical defaults', () {
      final rule = HydroDispatchAlertRule.fromJson(<String, dynamic>{
        'rule_id': '22222222-2222-2222-2222-222222222222',
        'plant_id': '11111111-1111-1111-1111-111111111111',
        'probability_threshold': 0.70,
        'min_probability_delta': 0.08,
        'window_lead_minutes': 90,
        'cooldown_minutes': 90,
        'notify_probability': true,
        'notify_window_approaching': true,
        'notify_observed_activity': true,
        'enabled': true,
      });

      expect(rule.probabilityThreshold, 0.70);
      expect(rule.minProbabilityDelta, 0.08);
      expect(rule.windowLeadMinutes, 90);
      expect(rule.cooldownMinutes, 90);
      expect(rule.notifyObservedActivity, isTrue);
      expect(rule.enabled, isTrue);
    });

    test('active field validation parses the backend snapshot without GPS', () {
      final session =
          HydroDispatchFieldValidationSession.fromJson(<String, dynamic>{
            'session_id': '33333333-3333-3333-3333-333333333333',
            'plant_id': '11111111-1111-1111-1111-111111111111',
            'plant_name': 'Frunzaru',
            'started_at': '2026-08-20T16:00:00Z',
            'predicted_window_start': '2026-08-20T15:15:00Z',
            'predicted_window_end': '2026-08-20T20:45:00Z',
            'predicted_window_probability': 0.66,
            'predicted_peak_probability': 0.75,
          });

      expect(session.plantName, 'Frunzaru');
      expect(session.predictedWindowProbability, closeTo(0.66, 0.000001));
      expect(session.predictedPeakProbability, closeTo(0.75, 0.000001));
    });

    test('field validation result keeps eligibility reason explicit', () {
      final result =
          HydroDispatchFieldValidationResult.fromJson(<String, dynamic>{
            'session_id': '33333333-3333-3333-3333-333333333333',
            'outcome': 'no_turbining_observed',
            'duration_minutes': 60.0,
            'prediction_window_overlap_minutes': 50.0,
            'calibration_eligible': true,
            'calibration_reason': 'negative_field_presence',
          });

      expect(result.calibrationEligible, isTrue);
      expect(result.calibrationReason, 'negative_field_presence');
      expect(result.durationMinutes, 60);
      expect(result.predictionWindowOverlapMinutes, 50);
    });

    test('field geofence keeps nearest CHE identity explicit', () {
      final geofence = HydroDispatchFieldGeofence.fromJson(<String, dynamic>{
        'eligible': false,
        'reason': 'nearest_plant_mismatch',
        'plant_id': 'draganesti',
        'plant_name': 'Drăgănești',
        'target_distance_km': 18.2,
        'confirmation_radius_km': 5.0,
        'ambiguity_margin_km': 0.75,
        'nearest_plant_id': 'izbiceni',
        'nearest_plant_name': 'Izbiceni',
        'nearest_distance_km': 0.8,
        'second_nearest_plant_id': 'rusanesti',
        'second_nearest_plant_name': 'Rusănești',
        'second_nearest_distance_km': 12.0,
        'nearest_gap_km': 11.2,
      });

      expect(geofence.eligible, isFalse);
      expect(geofence.isNearestPlant, isFalse);
      expect(geofence.nearestPlantName, 'Izbiceni');
      expect(geofence.reason, 'nearest_plant_mismatch');
    });

    test('field geofence rejects an ambiguous point between two CHE', () {
      final geofence = HydroDispatchFieldGeofence.fromJson(<String, dynamic>{
        'eligible': false,
        'reason': 'ambiguous_between_plants',
        'plant_id': 'ramnicu-valcea',
        'plant_name': 'Râmnicu Vâlcea',
        'target_distance_km': 2.795,
        'confirmation_radius_km': 5.0,
        'ambiguity_margin_km': 0.75,
        'nearest_plant_id': 'ramnicu-valcea',
        'nearest_plant_name': 'Râmnicu Vâlcea',
        'nearest_distance_km': 2.795,
        'second_nearest_plant_id': 'raureni',
        'second_nearest_plant_name': 'Râureni',
        'second_nearest_distance_km': 2.795,
        'nearest_gap_km': 0.0,
      });

      expect(geofence.eligible, isFalse);
      expect(geofence.isNearestPlant, isTrue);
      expect(geofence.isAmbiguous, isTrue);
      expect(geofence.nearestGapKm, 0.0);
    });
  });
}
