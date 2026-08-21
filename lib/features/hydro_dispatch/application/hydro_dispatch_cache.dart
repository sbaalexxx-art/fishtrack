import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../../services/hydro_dispatch_service.dart';

class HydroDispatchCachedSnapshot {
  const HydroDispatchCachedSnapshot({
    required this.savedAt,
    required this.forecasts,
    required this.aiContext,
  });

  final DateTime savedAt;
  final List<HydroDispatchDayForecast> forecasts;
  final List<HydroDispatchAiContext> aiContext;
}

/// Stores only the sanitized mobile Hydro Dispatch contract.
///
/// Raw ENTSO-E prices/MW, credentials, alert rules, device tokens and GPS
/// validation data are deliberately excluded. The cache is a resilience layer,
/// never a new source of truth: entries expire quickly and are rejected across
/// the Romania local-day boundary.
class HydroDispatchCache {
  const HydroDispatchCache();

  static const _prefix = 'hydro_dispatch_mobile_cache_v1_';
  static const maxAge = Duration(hours: 8);
  static bool _timezoneReady = false;

  Future<HydroDispatchCachedSnapshot?> restore(String plantId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(plantId);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(key);
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
      if (savedAt == null) {
        await prefs.remove(key);
        return null;
      }

      final now = DateTime.now();
      final age = now.difference(savedAt);
      if (age.isNegative && age.abs() > const Duration(minutes: 5)) {
        await prefs.remove(key);
        return null;
      }
      if (age > maxAge) {
        await prefs.remove(key);
        return null;
      }

      final forecastRows = json['forecasts'];
      final aiRows = json['ai_context'];
      final forecasts = forecastRows is List
          ? forecastRows
                .whereType<Map>()
                .map(
                  (row) => HydroDispatchDayForecast.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .where((row) => row.plantId == plantId)
                .toList(growable: false)
          : const <HydroDispatchDayForecast>[];
      final aiContext = aiRows is List
          ? aiRows
                .whereType<Map>()
                .map(
                  (row) => HydroDispatchAiContext.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .where((row) => row.plantId == plantId)
                .toList(growable: false)
          : const <HydroDispatchAiContext>[];

      if (forecasts.isEmpty && aiContext.isEmpty) {
        await prefs.remove(key);
        return null;
      }

      final today = forecasts.where((row) => row.dayOffset == 0).firstOrNull;
      if (today?.deliveryDate case final deliveryDate?) {
        if (!_sameRomaniaDay(deliveryDate, now)) {
          await prefs.remove(key);
          return null;
        }
      }

      return HydroDispatchCachedSnapshot(
        savedAt: savedAt,
        forecasts: forecasts,
        aiContext: aiContext,
      );
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  Future<void> save({
    required String plantId,
    required List<HydroDispatchDayForecast> forecasts,
    required List<HydroDispatchAiContext> aiContext,
  }) async {
    if (plantId.trim().isEmpty || (forecasts.isEmpty && aiContext.isEmpty)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, Object?>{
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'plant_id': plantId,
      'forecasts': forecasts.map(_forecastJson).toList(growable: false),
      'ai_context': aiContext.map(_aiJson).toList(growable: false),
    };
    await prefs.setString(_key(plantId), jsonEncode(payload));
  }

  Future<void> clear(String plantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(plantId));
  }

  static String _key(String plantId) => '$_prefix${plantId.trim()}';

  static bool _sameRomaniaDay(DateTime deliveryDate, DateTime now) {
    if (!_timezoneReady) {
      timezone_data.initializeTimeZones();
      _timezoneReady = true;
    }
    final ro = timezone.getLocation('Europe/Bucharest');
    final currentRo = timezone.TZDateTime.from(now.toUtc(), ro);
    // delivery_date is a DATE contract and parses as midnight. Compare its
    // calendar components directly; converting that midnight between zones
    // would incorrectly move the date on some devices.
    return deliveryDate.year == currentRo.year &&
        deliveryDate.month == currentRo.month &&
        deliveryDate.day == currentRo.day;
  }

  static Map<String, Object?> _forecastJson(HydroDispatchDayForecast row) =>
      <String, Object?>{
        'node_order': row.nodeOrder,
        'plant_id': row.plantId,
        'plant_name': row.plantName,
        'delivery_date': _dateOnly(row.deliveryDate),
        'day_offset': row.dayOffset,
        'availability_status': row.availabilityStatus,
        'window_start': row.windowStart?.toUtc().toIso8601String(),
        'window_end': row.windowEnd?.toUtc().toIso8601String(),
        'window_probability': row.windowProbability,
        'peak_probability': row.peakProbability,
        'confidence': row.confidence,
        'evidence_class': row.evidenceClass,
        'model_version': row.modelVersion,
        'updated_at': row.updatedAt?.toUtc().toIso8601String(),
        'system_signal_status': row.systemSignalStatus,
        'hydro_trend': row.hydroTrend,
        'corroboration_status': row.corroborationStatus,
        'local_hydrology_status': row.localHydrologyStatus,
        'local_rain_signal': row.localRainSignal,
        'local_target_count': row.localTargetCount,
      };

  static Map<String, Object?> _aiJson(HydroDispatchAiContext row) =>
      <String, Object?>{
        'plant_id': row.plantId,
        'plant_name': row.plantName,
        'day_offset': row.dayOffset,
        'availability_status': row.availabilityStatus,
        'window_start': row.windowStart?.toUtc().toIso8601String(),
        'window_end': row.windowEnd?.toUtc().toIso8601String(),
        'probability': row.probability,
        'peak_probability': row.peakProbability,
        'probability_band': row.probabilityBand,
        'confidence': row.confidence,
        'evidence_class': row.evidenceClass,
        'system_signal_status': row.systemSignalStatus,
        'hydro_trend': row.hydroTrend,
        'local_hydrology_status': row.localHydrologyStatus,
        'local_rain_signal': row.localRainSignal,
        'observed_state': row.observedState,
        'observed_started_at': row.observedStartedAt?.toUtc().toIso8601String(),
        'observed_last_confirmed_at': row.observedLastConfirmedAt
            ?.toUtc()
            .toIso8601String(),
        'observed_ended_at': row.observedEndedAt?.toUtc().toIso8601String(),
        'observed_confidence': row.observedConfidence,
        'observed_freshness_status': row.observedFreshnessStatus,
        'calibration_status': row.calibrationStatus,
        'calibration_sample_count': row.calibrationSampleCount,
        'truth_disclaimer': row.truthDisclaimer,
      };

  static String? _dateOnly(DateTime? value) {
    if (value == null) return null;
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
