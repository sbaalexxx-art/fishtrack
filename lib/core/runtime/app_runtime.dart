import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../context/current_location.dart';
import '../../services/diagnostics_service.dart';

enum AppRuntimeStatus { idle, starting, ready, degraded }

class AppRuntimeState {
  const AppRuntimeState({
    this.status = AppRuntimeStatus.idle,
    this.attempts = 0,
    this.locationStatus = CurrentLocationStatus.idle,
    this.lastCompletedAt,
  });

  final AppRuntimeStatus status;
  final int attempts;
  final CurrentLocationStatus locationStatus;
  final DateTime? lastCompletedAt;

  bool get hasStarted => status != AppRuntimeStatus.idle;
  bool get isStarting => status == AppRuntimeStatus.starting;
  bool get hasUsableLocation =>
      status == AppRuntimeStatus.ready &&
      (locationStatus == CurrentLocationStatus.cached ||
          locationStatus == CurrentLocationStatus.available);
}

class AppRuntimeController extends Notifier<AppRuntimeState> {
  Future<AppRuntimeState>? _activeRequest;

  @override
  AppRuntimeState build() => const AppRuntimeState();

  /// Starts the authenticated application session exactly once.
  Future<AppRuntimeState> start({required String languageCode}) {
    final active = _activeRequest;
    if (active != null) return active;
    if (state.hasStarted) return Future<AppRuntimeState>.value(state);
    return _runLocationRefresh(languageCode: languageCode, force: false);
  }

  /// Refreshes on resume only when the existing current GPS is not fresh.
  Future<AppRuntimeState> refreshIfStale({required String languageCode}) {
    final active = _activeRequest;
    if (active != null) return active;
    final current = ref.read(currentLocationProvider);
    final location = current.location;
    if (current.status == CurrentLocationStatus.available &&
        location != null &&
        location.isFreshAt(DateTime.now())) {
      return Future<AppRuntimeState>.value(state);
    }
    return _runLocationRefresh(languageCode: languageCode, force: false);
  }

  /// Explicit retry/manual refresh. This is the only path that forces GPS.
  Future<AppRuntimeState> forceRefresh({required String languageCode}) =>
      _runLocationRefresh(languageCode: languageCode, force: true);

  Future<AppRuntimeState> _runLocationRefresh({
    required String languageCode,
    required bool force,
  }) {
    final active = _activeRequest;
    if (active != null) return active;

    late final Future<AppRuntimeState> request;
    request = _refreshLocation(languageCode: languageCode, force: force)
        .whenComplete(() {
          if (identical(_activeRequest, request)) _activeRequest = null;
        });
    _activeRequest = request;
    return request;
  }

  Future<AppRuntimeState> _refreshLocation({
    required String languageCode,
    required bool force,
  }) async {
    final stopwatch = Stopwatch()..start();
    final attempts = state.attempts + 1;
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.location,
      operation: force ? 'runtime_force_refresh' : 'runtime_refresh',
      message: 'started',
      metadata: <String, Object?>{'attempt': attempts},
    );
    state = AppRuntimeState(
      status: AppRuntimeStatus.starting,
      attempts: attempts,
      locationStatus: ref.read(currentLocationProvider).status,
      lastCompletedAt: state.lastCompletedAt,
    );

    final location = await ref
        .read(currentLocationProvider.notifier)
        .refresh(languageCode: languageCode, force: force);
    final next = AppRuntimeState(
      status: location.hasUsableLocation
          ? AppRuntimeStatus.ready
          : AppRuntimeStatus.degraded,
      attempts: attempts,
      locationStatus: location.status,
      lastCompletedAt: DateTime.now(),
    );
    state = next;
    stopwatch.stop();
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.location,
      operation: force ? 'runtime_force_refresh' : 'runtime_refresh',
      message: next.status.name,
      duration: stopwatch.elapsed,
      metadata: <String, Object?>{
        'location_status': next.locationStatus.name,
        'has_usable_location': next.hasUsableLocation,
      },
    );
    return next;
  }
}

final appRuntimeProvider =
    NotifierProvider<AppRuntimeController, AppRuntimeState>(
      AppRuntimeController.new,
    );
