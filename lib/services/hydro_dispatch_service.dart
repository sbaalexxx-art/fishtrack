import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class HydroMapDispatchSnapshot {
  const HydroMapDispatchSnapshot({
    required this.plantId,
    required this.name,
    required this.availabilityStatus,
    required this.confidence,
    required this.evidenceClass,
    required this.observedState,
    required this.observedFreshness,
    required this.observedReportCount,
    this.damId,
    this.reservoirId,
    this.windowStart,
    this.windowEnd,
    this.windowProbability,
    this.peakProbability,
    this.updatedAt,
    this.observedConfidence,
  });

  factory HydroMapDispatchSnapshot.fromJson(Map<String, dynamic> json) =>
      HydroMapDispatchSnapshot(
        plantId: json['plant_id']?.toString() ?? '',
        damId: _text(json['dam_id']),
        reservoirId: _text(json['reservoir_id']),
        name: json['name']?.toString() ?? '',
        availabilityStatus:
            json['availability_status']?.toString() ?? 'UNAVAILABLE',
        windowStart: _dateTime(json['window_start']),
        windowEnd: _dateTime(json['window_end']),
        windowProbability: _double(json['window_probability']),
        peakProbability: _double(json['peak_probability']),
        confidence: json['confidence']?.toString() ?? 'unknown',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        updatedAt: _dateTime(json['updated_at']),
        observedState: json['observed_state']?.toString() ?? 'unknown',
        observedConfidence: _double(json['observed_confidence']),
        observedFreshness:
            json['observed_freshness']?.toString() ?? 'unavailable',
        observedReportCount: _int(json['observed_report_count']) ?? 0,
      );

  final String plantId;
  final String? damId;
  final String? reservoirId;
  final String name;
  final String availabilityStatus;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double? windowProbability;
  final double? peakProbability;
  final String confidence;
  final String evidenceClass;
  final DateTime? updatedAt;
  final String observedState;
  final double? observedConfidence;
  final String observedFreshness;
  final int observedReportCount;

  bool get isAvailable =>
      availabilityStatus == 'AVAILABLE' &&
      windowStart != null &&
      windowEnd != null &&
      windowProbability != null;
}

class HydroDispatchDayForecast {
  const HydroDispatchDayForecast({
    required this.nodeOrder,
    required this.plantId,
    required this.plantName,
    required this.deliveryDate,
    required this.dayOffset,
    required this.availabilityStatus,
    required this.confidence,
    required this.evidenceClass,
    required this.systemSignalStatus,
    required this.hydroTrend,
    required this.corroborationStatus,
    required this.localHydrologyStatus,
    required this.localRainSignal,
    required this.localTargetCount,
    this.windowStart,
    this.windowEnd,
    this.windowProbability,
    this.peakProbability,
    this.modelVersion,
    this.updatedAt,
  });

  factory HydroDispatchDayForecast.fromJson(Map<String, dynamic> json) =>
      HydroDispatchDayForecast(
        nodeOrder: _int(json['node_order']) ?? 0,
        plantId: json['plant_id']?.toString() ?? '',
        plantName: json['plant_name']?.toString() ?? '',
        deliveryDate: DateTime.tryParse(
          json['delivery_date']?.toString() ?? '',
        ),
        dayOffset: _int(json['day_offset']) ?? 0,
        availabilityStatus:
            json['availability_status']?.toString() ?? 'UNAVAILABLE',
        windowStart: _dateTime(json['window_start']),
        windowEnd: _dateTime(json['window_end']),
        windowProbability: _double(json['window_probability']),
        peakProbability: _double(json['peak_probability']),
        confidence: json['confidence']?.toString() ?? 'unknown',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        modelVersion: _text(json['model_version']),
        updatedAt: _dateTime(json['updated_at']),
        systemSignalStatus:
            json['system_signal_status']?.toString() ?? 'unavailable',
        hydroTrend: json['hydro_trend']?.toString() ?? 'unknown',
        corroborationStatus:
            json['corroboration_status']?.toString() ?? 'unavailable',
        localHydrologyStatus:
            json['local_hydrology_status']?.toString() ?? 'unavailable',
        localRainSignal: json['local_rain_signal']?.toString() ?? 'unknown',
        localTargetCount: _int(json['local_target_count']) ?? 0,
      );

  final int nodeOrder;
  final String plantId;
  final String plantName;
  final DateTime? deliveryDate;
  final int dayOffset;
  final String availabilityStatus;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double? windowProbability;
  final double? peakProbability;
  final String confidence;
  final String evidenceClass;
  final String? modelVersion;
  final DateTime? updatedAt;
  final String systemSignalStatus;
  final String hydroTrend;
  final String corroborationStatus;
  final String localHydrologyStatus;
  final String localRainSignal;
  final int localTargetCount;

  bool get isAvailable =>
      availabilityStatus == 'AVAILABLE' &&
      windowStart != null &&
      windowEnd != null &&
      windowProbability != null;

  bool get isTomorrow => dayOffset == 1;
}

class HydroDispatchAiContext {
  const HydroDispatchAiContext({
    required this.plantId,
    required this.plantName,
    required this.dayOffset,
    required this.availabilityStatus,
    required this.probabilityBand,
    required this.confidence,
    required this.evidenceClass,
    required this.systemSignalStatus,
    required this.hydroTrend,
    required this.localHydrologyStatus,
    required this.localRainSignal,
    required this.observedState,
    required this.observedFreshnessStatus,
    required this.calibrationStatus,
    required this.calibrationSampleCount,
    required this.truthDisclaimer,
    this.windowStart,
    this.windowEnd,
    this.probability,
    this.peakProbability,
    this.observedStartedAt,
    this.observedLastConfirmedAt,
    this.observedEndedAt,
    this.observedConfidence,
  });

  factory HydroDispatchAiContext.fromJson(Map<String, dynamic> json) =>
      HydroDispatchAiContext(
        plantId: json['plant_id']?.toString() ?? '',
        plantName: json['plant_name']?.toString() ?? '',
        dayOffset: _int(json['day_offset']) ?? 0,
        availabilityStatus:
            json['availability_status']?.toString() ?? 'UNAVAILABLE',
        windowStart: _dateTime(json['window_start']),
        windowEnd: _dateTime(json['window_end']),
        probability: _double(json['probability']),
        peakProbability: _double(json['peak_probability']),
        probabilityBand: json['probability_band']?.toString() ?? 'unknown',
        confidence: json['confidence']?.toString() ?? 'unknown',
        evidenceClass: json['evidence_class']?.toString() ?? 'UNKNOWN',
        systemSignalStatus:
            json['system_signal_status']?.toString() ?? 'unavailable',
        hydroTrend: json['hydro_trend']?.toString() ?? 'unknown',
        localHydrologyStatus:
            json['local_hydrology_status']?.toString() ?? 'unavailable',
        localRainSignal: json['local_rain_signal']?.toString() ?? 'unknown',
        observedState: json['observed_state']?.toString() ?? 'unknown',
        observedStartedAt: _dateTime(json['observed_started_at']),
        observedLastConfirmedAt: _dateTime(json['observed_last_confirmed_at']),
        observedEndedAt: _dateTime(json['observed_ended_at']),
        observedConfidence: _double(json['observed_confidence']),
        observedFreshnessStatus:
            json['observed_freshness_status']?.toString() ?? 'unavailable',
        calibrationStatus:
            json['calibration_status']?.toString() ?? 'uncalibrated',
        calibrationSampleCount: _int(json['calibration_sample_count']) ?? 0,
        truthDisclaimer: json['truth_disclaimer']?.toString() ?? '',
      );

  final String plantId;
  final String plantName;
  final int dayOffset;
  final String availabilityStatus;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final double? probability;
  final double? peakProbability;
  final String probabilityBand;
  final String confidence;
  final String evidenceClass;
  final String systemSignalStatus;
  final String hydroTrend;
  final String localHydrologyStatus;
  final String localRainSignal;
  final String observedState;
  final DateTime? observedStartedAt;
  final DateTime? observedLastConfirmedAt;
  final DateTime? observedEndedAt;
  final double? observedConfidence;
  final String observedFreshnessStatus;
  final String calibrationStatus;
  final int calibrationSampleCount;
  final String truthDisclaimer;
}

class HydroDispatchAlertRule {
  const HydroDispatchAlertRule({
    required this.id,
    required this.plantId,
    required this.probabilityThreshold,
    required this.minProbabilityDelta,
    required this.windowLeadMinutes,
    required this.cooldownMinutes,
    required this.notifyProbability,
    required this.notifyWindowApproaching,
    required this.notifyObservedActivity,
    required this.enabled,
  });

  factory HydroDispatchAlertRule.fromJson(Map<String, dynamic> json) =>
      HydroDispatchAlertRule(
        id: json['id']?.toString() ?? json['rule_id']?.toString() ?? '',
        plantId: json['plant_id']?.toString() ?? '',
        probabilityThreshold: _double(json['probability_threshold']) ?? .70,
        minProbabilityDelta: _double(json['min_probability_delta']) ?? .08,
        windowLeadMinutes: _int(json['window_lead_minutes']) ?? 90,
        cooldownMinutes: _int(json['cooldown_minutes']) ?? 90,
        notifyProbability: json['notify_probability'] != false,
        notifyWindowApproaching: json['notify_window_approaching'] != false,
        notifyObservedActivity: json['notify_observed_activity'] != false,
        enabled: json['enabled'] != false,
      );

  final String id;
  final String plantId;
  final double probabilityThreshold;
  final double minProbabilityDelta;
  final int windowLeadMinutes;
  final int cooldownMinutes;
  final bool notifyProbability;
  final bool notifyWindowApproaching;
  final bool notifyObservedActivity;
  final bool enabled;
}

class HydroDispatchFieldValidationSession {
  const HydroDispatchFieldValidationSession({
    required this.sessionId,
    required this.plantId,
    required this.plantName,
    required this.startedAt,
    this.predictedWindowStart,
    this.predictedWindowEnd,
    this.predictedWindowProbability,
    this.predictedPeakProbability,
  });

  factory HydroDispatchFieldValidationSession.fromJson(
    Map<String, dynamic> json,
  ) => HydroDispatchFieldValidationSession(
    sessionId: json['session_id']?.toString() ?? '',
    plantId: json['plant_id']?.toString() ?? '',
    plantName: json['plant_name']?.toString() ?? '',
    startedAt:
        _dateTime(json['started_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    predictedWindowStart: _dateTime(json['predicted_window_start']),
    predictedWindowEnd: _dateTime(json['predicted_window_end']),
    predictedWindowProbability: _double(json['predicted_window_probability']),
    predictedPeakProbability: _double(json['predicted_peak_probability']),
  );

  final String sessionId;
  final String plantId;
  final String plantName;
  final DateTime startedAt;
  final DateTime? predictedWindowStart;
  final DateTime? predictedWindowEnd;
  final double? predictedWindowProbability;
  final double? predictedPeakProbability;
}

class HydroDispatchFieldValidationResult {
  const HydroDispatchFieldValidationResult({
    required this.sessionId,
    required this.outcome,
    required this.durationMinutes,
    required this.predictionWindowOverlapMinutes,
    required this.calibrationEligible,
    required this.calibrationReason,
  });

  factory HydroDispatchFieldValidationResult.fromJson(
    Map<String, dynamic> json,
  ) => HydroDispatchFieldValidationResult(
    sessionId: json['session_id']?.toString() ?? '',
    outcome: json['outcome']?.toString() ?? 'unknown',
    durationMinutes: _double(json['duration_minutes']) ?? 0,
    predictionWindowOverlapMinutes:
        _double(json['prediction_window_overlap_minutes']) ?? 0,
    calibrationEligible: json['calibration_eligible'] == true,
    calibrationReason: json['calibration_reason']?.toString() ?? 'not_eligible',
  );

  final String sessionId;
  final String outcome;
  final double durationMinutes;
  final double predictionWindowOverlapMinutes;
  final bool calibrationEligible;
  final String calibrationReason;
}

class HydroDispatchService {
  const HydroDispatchService({SupabaseClient? client}) : _client = client;

  static const canonicalSavedItemType = 'hydropower_plant';

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<HydroMapDispatchSnapshot?> getMapDispatchSnapshot(String plantId) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_hydro_map_dispatch_overlay_v1',
        );
        if (response is! List) return null;
        for (final row in response.whereType<Map>()) {
          final snapshot = HydroMapDispatchSnapshot.fromJson(
            Map<String, dynamic>.from(row),
          );
          if (snapshot.plantId == plantId) return snapshot;
        }
        return null;
      });

  Future<List<HydroDispatchDayForecast>> getTodayTomorrow(String plantId) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_hydro_dispatch_olt_today_tomorrow_v3',
        );
        if (response is! List) return const <HydroDispatchDayForecast>[];
        final rows =
            response
                .whereType<Map>()
                .map(
                  (row) => HydroDispatchDayForecast.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .where((row) => row.plantId == plantId)
                .toList(growable: false)
              ..sort((a, b) => a.dayOffset.compareTo(b.dayOffset));
        return rows;
      });

  Future<List<HydroDispatchAiContext>> getAiContext(String plantId) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_hydro_dispatch_olt_ai_context_v1',
          params: <String, Object?>{'p_plant_id': plantId},
        );
        if (response is! List) return const <HydroDispatchAiContext>[];
        final rows =
            response
                .whereType<Map>()
                .map(
                  (row) => HydroDispatchAiContext.fromJson(
                    Map<String, dynamic>.from(row),
                  ),
                )
                .toList(growable: false)
              ..sort((a, b) => a.dayOffset.compareTo(b.dayOffset));
        return rows;
      });

  Future<HydroDispatchAlertRule?> getAlertRule(
    String plantId,
  ) => _guard(() async {
    final response = await _supabase
        .from('hydro_dispatch_alert_rules')
        .select(
          'id,plant_id,probability_threshold,min_probability_delta,window_lead_minutes,cooldown_minutes,notify_probability,notify_window_approaching,notify_observed_activity,enabled',
        )
        .eq('plant_id', plantId)
        .limit(1);
    if (response.isEmpty) return null;
    return HydroDispatchAlertRule.fromJson(
      Map<String, dynamic>.from(response.first),
    );
  });

  Future<HydroDispatchAlertRule> enableDefaultAlert(String plantId) =>
      upsertAlertRule(plantId: plantId);

  Future<HydroDispatchAlertRule> upsertAlertRule({
    required String plantId,
    double probabilityThreshold = .70,
    double minProbabilityDelta = .08,
    int windowLeadMinutes = 90,
    int cooldownMinutes = 90,
    bool notifyProbability = true,
    bool notifyWindowApproaching = true,
    bool notifyObservedActivity = true,
    bool enabled = true,
    bool saveFavorite = true,
  }) => _guard(() async {
    final response = await _supabase.rpc(
      'upsert_hydro_dispatch_alert_rule_v1',
      params: <String, Object?>{
        'p_plant_id': plantId,
        'p_probability_threshold': probabilityThreshold,
        'p_min_probability_delta': minProbabilityDelta,
        'p_window_lead_minutes': windowLeadMinutes,
        'p_cooldown_minutes': cooldownMinutes,
        'p_notify_probability': notifyProbability,
        'p_notify_window_approaching': notifyWindowApproaching,
        'p_notify_observed_activity': notifyObservedActivity,
        'p_enabled': enabled,
        'p_save_favorite': saveFavorite,
      },
    );
    if (response is! Map) {
      throw const HydroDispatchException(
        'Hydro Dispatch alert could not be saved.',
      );
    }
    return HydroDispatchAlertRule.fromJson(Map<String, dynamic>.from(response));
  });

  Future<bool> deleteAlertRule(String plantId, {bool removeFavorite = false}) =>
      _guard(() async {
        final response = await _supabase.rpc(
          'delete_hydro_dispatch_alert_rule_v1',
          params: <String, Object?>{
            'p_plant_id': plantId,
            'p_remove_favorite': removeFavorite,
          },
        );
        return response == true;
      });

  Future<String> startFieldValidation({
    required String plantId,
    required double latitude,
    required double longitude,
  }) => _guard(() async {
    final response = await _supabase.rpc(
      'start_hydro_dispatch_field_validation_v1',
      params: <String, Object?>{
        'p_plant_id': plantId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
    final id = response?.toString() ?? '';
    if (id.isEmpty) {
      throw const HydroDispatchException(
        'Field validation could not be started.',
      );
    }
    return id;
  });

  Future<HydroDispatchFieldValidationSession?> getActiveFieldValidation() =>
      _guard(() async {
        final response = await _supabase.rpc(
          'get_my_active_hydro_dispatch_field_validation_v1',
        );
        if (response is! List || response.isEmpty || response.first is! Map) {
          return null;
        }
        return HydroDispatchFieldValidationSession.fromJson(
          Map<String, dynamic>.from(response.first as Map),
        );
      });

  Future<HydroDispatchFieldValidationResult> finishFieldValidation({
    required String sessionId,
    required String outcome,
    required double latitude,
    required double longitude,
  }) => _guard(() async {
    final response = await _supabase.rpc(
      'finish_hydro_dispatch_field_validation_v1',
      params: <String, Object?>{
        'p_session_id': sessionId,
        'p_outcome': outcome,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
    if (response is! Map) {
      throw const HydroDispatchException(
        'Field validation could not be finished.',
      );
    }
    return HydroDispatchFieldValidationResult.fromJson(
      Map<String, dynamic>.from(response),
    );
  });

  Future<void> submitObservedEvent({
    required String reportId,
    required String plantId,
    required String eventType,
    DateTime? observedAt,
    String observedAtPrecision = 'reported',
  }) => _guard(() async {
    await _supabase.rpc(
      'submit_hydro_dispatch_observation_v1',
      params: <String, Object?>{
        'p_report_id': reportId,
        'p_plant_id': plantId,
        'p_event_type': eventType,
        if (observedAt != null)
          'p_observed_at': observedAt.toUtc().toIso8601String(),
        'p_observed_at_precision': observedAtPrecision,
      },
    );
  });

  User _requireUser() {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const HydroDispatchException('Authentication is required.');
    }
    return user;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      _requireUser();
      return await operation().timeout(const Duration(seconds: 20));
    } on HydroDispatchException {
      rethrow;
    } on SocketException {
      throw const HydroDispatchException('No internet connection.');
    } on TimeoutException {
      throw const HydroDispatchException(
        'Hydro Dispatch request timed out. Please retry.',
      );
    } on PostgrestException catch (error) {
      throw HydroDispatchException(
        error.message.trim().isEmpty
            ? 'Hydro Dispatch is unavailable. Please retry.'
            : error.message,
      );
    }
  }
}

class HydroDispatchException implements Exception {
  const HydroDispatchException(this.message);
  final String message;

  @override
  String toString() => message;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'null' ? null : text;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _dateTime(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '');
