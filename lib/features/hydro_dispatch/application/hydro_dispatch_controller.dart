import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/diagnostics_service.dart';
import '../../../services/hydro_dispatch_service.dart';

enum HydroDispatchMobileStatus { idle, loading, ready, degraded, error }

class HydroDispatchMobileState {
  const HydroDispatchMobileState({
    this.status = HydroDispatchMobileStatus.idle,
    this.plantId,
    this.forecasts = const <HydroDispatchDayForecast>[],
    this.aiContext = const <HydroDispatchAiContext>[],
    this.alertRule,
    this.activeValidation,
    this.lastCompletedValidation,
    this.lastError,
    this.refreshedAt,
    this.isAlertMutationRunning = false,
    this.isValidationMutationRunning = false,
  });

  final HydroDispatchMobileStatus status;
  final String? plantId;
  final List<HydroDispatchDayForecast> forecasts;
  final List<HydroDispatchAiContext> aiContext;
  final HydroDispatchAlertRule? alertRule;
  final HydroDispatchFieldValidationSession? activeValidation;
  final HydroDispatchFieldValidationResult? lastCompletedValidation;
  final String? lastError;
  final DateTime? refreshedAt;
  final bool isAlertMutationRunning;
  final bool isValidationMutationRunning;

  bool get isLoading => status == HydroDispatchMobileStatus.loading;
  bool get hasForecast => forecasts.isNotEmpty;
  bool get hasUsableData => hasForecast || aiContext.isNotEmpty;
  bool get alertEnabled => alertRule?.enabled == true;

  HydroDispatchDayForecast? get today =>
      forecasts.where((item) => item.dayOffset == 0).firstOrNull;

  HydroDispatchDayForecast? get tomorrow =>
      forecasts.where((item) => item.dayOffset == 1).firstOrNull;

  HydroDispatchMobileState copyWith({
    HydroDispatchMobileStatus? status,
    String? plantId,
    List<HydroDispatchDayForecast>? forecasts,
    List<HydroDispatchAiContext>? aiContext,
    HydroDispatchAlertRule? alertRule,
    bool clearAlertRule = false,
    HydroDispatchFieldValidationSession? activeValidation,
    bool clearActiveValidation = false,
    HydroDispatchFieldValidationResult? lastCompletedValidation,
    bool clearLastCompletedValidation = false,
    String? lastError,
    bool clearLastError = false,
    DateTime? refreshedAt,
    bool? isAlertMutationRunning,
    bool? isValidationMutationRunning,
  }) => HydroDispatchMobileState(
    status: status ?? this.status,
    plantId: plantId ?? this.plantId,
    forecasts: forecasts ?? this.forecasts,
    aiContext: aiContext ?? this.aiContext,
    alertRule: clearAlertRule ? null : alertRule ?? this.alertRule,
    activeValidation: clearActiveValidation
        ? null
        : activeValidation ?? this.activeValidation,
    lastCompletedValidation: clearLastCompletedValidation
        ? null
        : lastCompletedValidation ?? this.lastCompletedValidation,
    lastError: clearLastError ? null : lastError ?? this.lastError,
    refreshedAt: refreshedAt ?? this.refreshedAt,
    isAlertMutationRunning:
        isAlertMutationRunning ?? this.isAlertMutationRunning,
    isValidationMutationRunning:
        isValidationMutationRunning ?? this.isValidationMutationRunning,
  );
}

final hydroDispatchServiceProvider = Provider<HydroDispatchService>(
  (ref) => const HydroDispatchService(),
);

class _HydroLoadResult<T> {
  const _HydroLoadResult.success(this.value) : error = null;
  const _HydroLoadResult.failure(this.error) : value = null;

  final T? value;
  final Object? error;

  bool get failed => error != null;
}

class HydroDispatchMobileController extends Notifier<HydroDispatchMobileState> {
  Future<HydroDispatchMobileState>? _activeRefresh;

  HydroDispatchService get _service => ref.read(hydroDispatchServiceProvider);

  @override
  HydroDispatchMobileState build() => const HydroDispatchMobileState();

  Future<HydroDispatchMobileState> refresh(
    String plantId, {
    bool force = false,
  }) {
    final normalized = plantId.trim();
    if (normalized.isEmpty) {
      state = const HydroDispatchMobileState(
        status: HydroDispatchMobileStatus.error,
        lastError: 'Hydropower plant is required.',
      );
      return Future<HydroDispatchMobileState>.value(state);
    }

    final active = _activeRefresh;
    if (active != null) return active;

    if (!force &&
        state.plantId == normalized &&
        state.refreshedAt != null &&
        DateTime.now().difference(state.refreshedAt!).inMinutes < 5) {
      return Future<HydroDispatchMobileState>.value(state);
    }

    late final Future<HydroDispatchMobileState> request;
    request = _refresh(normalized).whenComplete(() {
      if (identical(_activeRefresh, request)) _activeRefresh = null;
    });
    _activeRefresh = request;
    return request;
  }

  Future<HydroDispatchMobileState> retry() async {
    final plantId = state.plantId;
    if (plantId == null || plantId.isEmpty) return state;
    return refresh(plantId, force: true);
  }

  Future<_HydroLoadResult<T>> _capture<T>(Future<T> request) async {
    try {
      return _HydroLoadResult<T>.success(await request);
    } on Object catch (error) {
      return _HydroLoadResult<T>.failure(error);
    }
  }

  Future<HydroDispatchMobileState> _refresh(String plantId) async {
    final previous = state;
    final samePlant = previous.plantId == plantId;
    state = HydroDispatchMobileState(
      status: HydroDispatchMobileStatus.loading,
      plantId: plantId,
      forecasts: samePlant
          ? previous.forecasts
          : const <HydroDispatchDayForecast>[],
      aiContext: samePlant
          ? previous.aiContext
          : const <HydroDispatchAiContext>[],
      alertRule: samePlant ? previous.alertRule : null,
      activeValidation: samePlant ? previous.activeValidation : null,
      lastCompletedValidation: samePlant
          ? previous.lastCompletedValidation
          : null,
      refreshedAt: samePlant ? previous.refreshedAt : null,
      isAlertMutationRunning: previous.isAlertMutationRunning,
      isValidationMutationRunning: previous.isValidationMutationRunning,
    );

    final stopwatch = Stopwatch()..start();

    final forecastsRequest = _capture<List<HydroDispatchDayForecast>>(
      _service.getTodayTomorrow(plantId),
    );
    final aiRequest = _capture<List<HydroDispatchAiContext>>(
      _service.getAiContext(plantId),
    );
    final ruleRequest = _capture<HydroDispatchAlertRule?>(
      _service.getAlertRule(plantId),
    );
    final validationRequest = _capture<HydroDispatchFieldValidationSession?>(
      _service.getActiveFieldValidation(),
    );

    final forecastsResult = await forecastsRequest;
    final aiResult = await aiRequest;
    final ruleResult = await ruleRequest;
    final validationResult = await validationRequest;

    final forecasts = forecastsResult.value ??
        (samePlant
            ? previous.forecasts
            : const <HydroDispatchDayForecast>[]);
    final ai = aiResult.value ??
        (samePlant ? previous.aiContext : const <HydroDispatchAiContext>[]);
    final rule = ruleResult.failed
        ? (samePlant ? previous.alertRule : null)
        : ruleResult.value;
    final activeValidation = validationResult.failed
        ? (samePlant ? previous.activeValidation : null)
        : validationResult.value;

    final failures = <Object>[
      ?forecastsResult.error,
      ?aiResult.error,
      ?ruleResult.error,
      ?validationResult.error,
    ];
    final usable = forecasts.isNotEmpty || ai.isNotEmpty;
    final nextStatus = failures.isEmpty
        ? (usable
              ? HydroDispatchMobileStatus.ready
              : HydroDispatchMobileStatus.degraded)
        : (usable
              ? HydroDispatchMobileStatus.degraded
              : HydroDispatchMobileStatus.error);

    stopwatch.stop();
    state = HydroDispatchMobileState(
      status: nextStatus,
      plantId: plantId,
      forecasts: forecasts,
      aiContext: ai,
      alertRule: rule,
      activeValidation: activeValidation,
      lastCompletedValidation: samePlant
          ? previous.lastCompletedValidation
          : null,
      lastError: failures.isEmpty ? null : failures.first.toString(),
      refreshedAt: DateTime.now(),
      isAlertMutationRunning: state.isAlertMutationRunning,
      isValidationMutationRunning: state.isValidationMutationRunning,
    );

    DiagnosticsService.instance.record(
      category: DiagnosticCategory.ai,
      operation: 'hydro_dispatch_refresh',
      message: state.status.name,
      duration: stopwatch.elapsed,
      metadata: <String, Object?>{
        'plant_id': plantId,
        'forecast_rows': forecasts.length,
        'ai_rows': ai.length,
        'alert_enabled': rule?.enabled == true,
        'field_validation_active': activeValidation != null,
        'partial_failures': failures.length,
      },
    );

    if (failures.isNotEmpty) {
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.ai,
        operation: 'hydro_dispatch_refresh_partial',
        error: failures.first,
        metadata: <String, Object?>{
          'plant_id': plantId,
          'failure_count': failures.length,
          'usable_data_preserved': usable,
        },
      );
    }
    return state;
  }

  Future<HydroDispatchAlertRule?> enableDefaultAlert() async {
    final plantId = state.plantId;
    if (plantId == null || plantId.isEmpty || state.isAlertMutationRunning) {
      return state.alertRule;
    }
    state = state.copyWith(
      isAlertMutationRunning: true,
      clearLastError: true,
    );
    try {
      final rule = await _service.enableDefaultAlert(plantId);
      state = state.copyWith(
        alertRule: rule,
        isAlertMutationRunning: false,
      );
      return rule;
    } on Object catch (error, stackTrace) {
      state = state.copyWith(
        isAlertMutationRunning: false,
        lastError: error.toString(),
      );
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'hydro_dispatch_enable_alert',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'plant_id': plantId},
      );
      return null;
    }
  }

  Future<bool> disableAlert({bool removeFavorite = false}) async {
    final plantId = state.plantId;
    if (plantId == null || plantId.isEmpty || state.isAlertMutationRunning) {
      return false;
    }
    state = state.copyWith(
      isAlertMutationRunning: true,
      clearLastError: true,
    );
    try {
      final deleted = await _service.deleteAlertRule(
        plantId,
        removeFavorite: removeFavorite,
      );
      state = state.copyWith(
        clearAlertRule: deleted,
        isAlertMutationRunning: false,
      );
      return deleted;
    } on Object catch (error, stackTrace) {
      state = state.copyWith(
        isAlertMutationRunning: false,
        lastError: error.toString(),
      );
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'hydro_dispatch_disable_alert',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'plant_id': plantId},
      );
      return false;
    }
  }

  Future<HydroDispatchFieldValidationSession?> startFieldValidation({
    required double latitude,
    required double longitude,
  }) async {
    final plantId = state.plantId;
    if (plantId == null ||
        plantId.isEmpty ||
        state.isValidationMutationRunning) {
      return state.activeValidation;
    }
    state = state.copyWith(
      isValidationMutationRunning: true,
      clearLastError: true,
    );
    try {
      await _service.startFieldValidation(
        plantId: plantId,
        latitude: latitude,
        longitude: longitude,
      );
      final active = await _service.getActiveFieldValidation();
      state = state.copyWith(
        activeValidation: active,
        clearLastCompletedValidation: true,
        isValidationMutationRunning: false,
      );
      return active;
    } on Object catch (error, stackTrace) {
      state = state.copyWith(
        isValidationMutationRunning: false,
        lastError: error.toString(),
      );
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.location,
        operation: 'hydro_dispatch_field_validation_start',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'plant_id': plantId},
      );
      return null;
    }
  }

  Future<HydroDispatchFieldValidationResult?> finishFieldValidation({
    required String outcome,
    required double latitude,
    required double longitude,
  }) async {
    final active = state.activeValidation;
    if (active == null || state.isValidationMutationRunning) return null;
    state = state.copyWith(
      isValidationMutationRunning: true,
      clearLastError: true,
    );
    try {
      final result = await _service.finishFieldValidation(
        sessionId: active.sessionId,
        outcome: outcome,
        latitude: latitude,
        longitude: longitude,
      );
      state = state.copyWith(
        clearActiveValidation: true,
        lastCompletedValidation: result,
        isValidationMutationRunning: false,
      );
      return result;
    } on Object catch (error, stackTrace) {
      state = state.copyWith(
        isValidationMutationRunning: false,
        lastError: error.toString(),
      );
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.location,
        operation: 'hydro_dispatch_field_validation_finish',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{'plant_id': active.plantId},
      );
      return null;
    }
  }

  void clear() {
    _activeRefresh = null;
    state = const HydroDispatchMobileState();
  }
}

final hydroDispatchMobileProvider =
    NotifierProvider<HydroDispatchMobileController, HydroDispatchMobileState>(
      HydroDispatchMobileController.new,
    );
