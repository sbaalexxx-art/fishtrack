import 'package:flutter_test/flutter_test.dart';
import 'package:fishtrack/services/hydro_dispatch_service.dart';
import 'package:fishtrack/services/saved_items_service.dart';

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

    test('tomorrow not-yet-published never looks available', () {
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
    });

    test('AI context keeps observed and estimated evidence distinct', () {
      final context = HydroDispatchAiContext.fromJson(<String, dynamic>{
        'plant_id': '11111111-1111-1111-1111-111111111111',
        'plant_name': 'Frunzaru',
        'day_offset': 0,
        'availability_status': 'AVAILABLE',
        'probability': 0.66,
        'peak_probability': 0.75,
        'probability_band': 'possible',
        'confidence': 'low',
        'evidence_class': 'ESTIMATED',
        'system_signal_status': 'fresh',
        'hydro_trend': 'falling',
        'local_hydrology_status': 'available',
        'local_rain_signal': 'dry',
        'observed_state': 'active',
        'observed_confidence': 0.9,
        'observed_freshness_status': 'fresh',
        'calibration_status': 'uncalibrated',
        'calibration_sample_count': 0,
        'truth_disclaimer': 'Probability is not confirmed generation.',
      });

      expect(context.evidenceClass, 'ESTIMATED');
      expect(context.observedState, 'active');
      expect(context.observedConfidence, closeTo(0.9, 0.000001));
      expect(context.calibrationSampleCount, 0);
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
  });
}
