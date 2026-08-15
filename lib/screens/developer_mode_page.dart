import 'dart:async';

import 'package:flutter/material.dart' hide DiagnosticLevel;
import 'package:flutter/services.dart' hide DiagnosticLevel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/context/current_location.dart';
import '../core/context/selected_context.dart';
import '../core/runtime/app_runtime.dart';
import '../models/station.dart';
import '../services/build_mode_service.dart';
import '../services/diagnostics_service.dart';
import '../services/firebase_observability_service.dart';
import '../services/firebase_push_service.dart';
import '../services/notification_service.dart';
import '../services/water_service.dart';
import '../services/weather_service.dart';

class DeveloperModePage extends ConsumerStatefulWidget {
  const DeveloperModePage({super.key});

  static const appVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: '1.0.0',
  );

  @override
  ConsumerState<DeveloperModePage> createState() => _DeveloperModePageState();
}

class _DeveloperModePageState extends ConsumerState<DeveloperModePage> {
  String? _busyAction;

  DiagnosticsService get _diagnostics => DiagnosticsService.instance;

  @override
  Widget build(BuildContext context) {
    if (!BuildModeService.isDeveloperVisible) {
      return const SizedBox.shrink();
    }

    final effectiveTier = ref.watch(fluviAccessTierProvider);
    final entitlementMode = ref.watch(fluviDeveloperEntitlementModeProvider);
    final runtime = ref.watch(appRuntimeProvider);
    final currentLocation = ref.watch(currentLocationProvider);
    final selectedContext = ref.watch(selectedContextProvider);
    final session = Supabase.instance.client.auth.currentSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PO Developer Console'),
        actions: [
          IconButton(
            tooltip: 'Copy diagnostics',
            onPressed: () => _copyDiagnostics(
              runtime: runtime,
              location: currentLocation,
              selectedContext: selectedContext,
              effectiveTier: effectiveTier,
            ),
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: _diagnostics.revision,
        builder: (context, _, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _sectionTitle('BUILD & ACCESS'),
            Card(
              child: Column(
                children: [
                  _info('App version', DeveloperModePage.appVersion),
                  _info('Environment', BuildModeService.environment),
                  _info('Signed in', session == null ? 'NO' : 'YES'),
                  _info('User', session?.user.id.substring(0, 8) ?? '—'),
                  _info('Effective tier', effectiveTier.name.toUpperCase()),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PO entitlement override',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Internal build only. Public release remains Store-controlled.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<FluviDeveloperEntitlementMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: FluviDeveloperEntitlementMode.forceFree,
                          label: Text('Free'),
                          icon: Icon(Icons.lock_open_rounded),
                        ),
                        ButtonSegment(
                          value: FluviDeveloperEntitlementMode.forcePremium,
                          label: Text('Pro'),
                          icon: Icon(Icons.workspace_premium_rounded),
                        ),
                        ButtonSegment(
                          value: FluviDeveloperEntitlementMode.storeReal,
                          label: Text('Store'),
                          icon: Icon(Icons.storefront_rounded),
                        ),
                      ],
                      selected: <FluviDeveloperEntitlementMode>{
                        entitlementMode,
                      },
                      onSelectionChanged: (selection) {
                        final mode = selection.first;
                        unawaited(
                          ref
                              .read(
                                fluviDeveloperEntitlementModeProvider.notifier,
                              )
                              .setMode(mode),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('RUNTIME CONTEXT'),
            Card(
              child: Column(
                children: [
                  _info('Runtime', runtime.status.name),
                  _info('Runtime attempts', runtime.attempts.toString()),
                  _info('GPS status', currentLocation.status.name),
                  _info(
                    'Physical location',
                    _coordinates(
                      currentLocation.location?.latitude,
                      currentLocation.location?.longitude,
                    ),
                  ),
                  _info(
                    'Selected context',
                    selectedContext?.stationName ??
                        selectedContext?.waterName ??
                        selectedContext?.locationName ??
                        '—',
                  ),
                  _info(
                    'Selected coordinates',
                    _coordinates(
                      selectedContext?.latitude,
                      selectedContext?.longitude,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('LIVE HEALTH CHECKS'),
            Card(
              child: Column(
                children: [
                  _action(
                    icon: Icons.storage_rounded,
                    label: 'Test Supabase',
                    keyName: 'supabase',
                    onTap: _testSupabase,
                  ),
                  _action(
                    icon: Icons.water_rounded,
                    label: 'Test Water v2 runtime',
                    keyName: 'water',
                    onTap: _testWater,
                  ),
                  _action(
                    icon: Icons.cloud_rounded,
                    label: 'Test Open-Meteo runtime',
                    keyName: 'weather',
                    onTap: _testWeather,
                  ),
                  _action(
                    icon: Icons.notifications_active_rounded,
                    label: 'Test Notification inbox',
                    keyName: 'notifications',
                    onTap: _testNotifications,
                  ),
                  _action(
                    icon: Icons.my_location_rounded,
                    label: 'Force runtime/GPS refresh',
                    keyName: 'runtime',
                    onTap: _forceRuntimeRefresh,
                  ),
                  _action(
                    icon: Icons.delete_sweep_rounded,
                    label: 'Clear Water + Weather cache',
                    keyName: 'cache',
                    onTap: _clearRuntimeCaches,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('FIREBASE / PUSH'),
            _firebaseCard(),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  _action(
                    icon: Icons.analytics_outlined,
                    label: 'Send Analytics test event',
                    keyName: 'firebase-analytics',
                    onTap: _testFirebaseAnalytics,
                  ),
                  _action(
                    icon: Icons.bug_report_outlined,
                    label: 'Record Crashlytics non-fatal',
                    keyName: 'firebase-crashlytics',
                    onTap: _testCrashlytics,
                  ),
                  _action(
                    icon: Icons.speed_rounded,
                    label: 'Run Performance test trace',
                    keyName: 'firebase-performance',
                    onTap: _testPerformance,
                  ),
                  _action(
                    icon: Icons.notifications_active_outlined,
                    label: 'Refresh + register FCM token',
                    keyName: 'firebase-fcm',
                    onTap: _refreshFcm,
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('Copy FCM test token'),
                    subtitle: const Text(
                      'Explicit PO action only; token is excluded from diagnostics.',
                    ),
                    onTap: _busyAction == null ? _copyFcmToken : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('OBSERVABILITY'),
            _observabilityCard(),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('View recent diagnostics'),
                    subtitle: Text(
                      '${_diagnostics.events.length} events retained',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _showLogs,
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy_all_rounded),
                    title: const Text('Copy diagnostic report'),
                    subtitle: const Text('Secrets and tokens are redacted'),
                    onTap: () => _copyDiagnostics(
                      runtime: runtime,
                      location: currentLocation,
                      selectedContext: selectedContext,
                      effectiveTier: effectiveTier,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Clear diagnostic log'),
                    onTap: () {
                      _diagnostics.clear();
                      _showMessage('Diagnostic log cleared.');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Security: this console does not record request bodies, auth tokens, '
              'API keys, passwords or image bytes. It is available only in debug '
              'or explicitly compiled PO internal builds.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _firebaseCard() {
    final firebase = FirebaseObservabilityService.instance.snapshot;
    final push = FirebasePushService.instance.snapshot;
    return Card(
      child: Column(
        children: [
          _info('Firebase initialized', firebase.initialized ? 'YES' : 'NO'),
          _info('Firebase project', firebase.projectId ?? '—'),
          _info(
            'Telemetry collection',
            firebase.collectionEnabled ? 'ENABLED' : 'DISABLED',
          ),
          _info('FCM initialized', push.initialized ? 'YES' : 'NO'),
          _info('Notification permission', push.authorizationStatus),
          _info('FCM token', push.hasToken ? 'AVAILABLE' : 'MISSING'),
          _info(
            'Supabase device registry',
            push.registeredWithSupabase ? 'REGISTERED' : 'NOT REGISTERED',
          ),
          if (firebase.lastInitializationError != null)
            _info('Firebase error', firebase.lastInitializationError!),
          if (push.lastRegistrationError != null)
            _info('FCM error', push.lastRegistrationError!),
        ],
      ),
    );
  }

  Widget _observabilityCard() {
    final events = _diagnostics.events;
    final errors = events.where((event) => event.isError).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('Events', events.length),
            _metric('Errors', errors),
            _metric('Persisted', _diagnostics.persistedErrors.length),
            _metric(
              'Network',
              _diagnostics.countFor(DiagnosticCategory.network),
            ),
            _metric('Water', _diagnostics.countFor(DiagnosticCategory.water)),
            _metric(
              'Weather',
              _diagnostics.countFor(DiagnosticCategory.weather),
            ),
            _metric(
              'Supabase',
              _diagnostics.countFor(DiagnosticCategory.supabase),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, int value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text('$label  $value'),
  );

  Future<void> _testSupabase() => _runAction('supabase', () async {
    await _diagnostics.trace<void>(
      category: DiagnosticCategory.supabase,
      operation: 'health_check',
      action: () async {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('id')
            .limit(1);
        _diagnostics.record(
          category: DiagnosticCategory.supabase,
          operation: 'health_check_result',
          message: 'Supabase query succeeded',
          metadata: <String, Object?>{'rows': response.length},
        );
      },
    );
    _showMessage('Supabase: PASS');
  });

  Future<void> _testWater() => _runAction('water', () async {
    final water = WaterService();
    final stations = await _diagnostics.trace<List<Station>>(
      category: DiagnosticCategory.water,
      operation: 'station_catalog',
      action: () => water.getStations(forceRefresh: true),
    );
    if (stations.isEmpty) throw StateError('No Water stations available.');
    final selectedId = ref.read(selectedContextProvider)?.stationId;
    Station station = stations.first;
    if (selectedId != null) {
      for (final candidate in stations) {
        if (candidate.id == selectedId) {
          station = candidate;
          break;
        }
      }
    }
    final result = await _diagnostics.trace(
      category: DiagnosticCategory.water,
      operation: 'water_v2_runtime',
      metadata: <String, Object?>{'station_id': station.id},
      action: () => water.getWaterUiResult(
        station,
        limit: 30,
        historyWindow: const Duration(days: 30),
        forceRefresh: true,
      ),
    );
    _diagnostics.record(
      category: DiagnosticCategory.water,
      operation: 'water_v2_result',
      message: result.status.name,
      metadata: <String, Object?>{
        'station_id': station.id,
        'source': result.sourceName,
        'level_cm': result.latestReading?.value,
        'delta_cm': result.deltaCm,
        'history_points': result.history.length,
        'stale': result.isStale,
      },
    );
    if (result.latestReading == null) {
      throw StateError('Water returned no current reading.');
    }
    _showMessage(
      'Water PASS · ${station.name}: ${result.latestReading!.value.toStringAsFixed(0)} cm · ${result.history.length} points',
    );
  });

  Future<void> _testWeather() => _runAction('weather', () async {
    final selected = ref.read(selectedContextProvider);
    final physical = ref.read(currentLocationProvider).location;
    final latitude = selected?.latitude ?? physical?.latitude;
    final longitude = selected?.longitude ?? physical?.longitude;
    if (latitude == null || longitude == null) {
      throw StateError('No real coordinates are currently available.');
    }
    final result = await _diagnostics.trace(
      category: DiagnosticCategory.weather,
      operation: 'open_meteo_runtime',
      metadata: <String, Object?>{
        'context': selected?.stationId ?? selected?.waterId ?? 'physical_gps',
      },
      action: () => WeatherService().getHomeWeatherResultForLocation(
        latitude: latitude,
        longitude: longitude,
        forceRefresh: true,
      ),
    );
    _diagnostics.record(
      category: DiagnosticCategory.weather,
      operation: 'weather_result',
      message: result.status.name,
      metadata: <String, Object?>{
        'temperature_c': result.data?.temperature,
        'wind_kmh': result.data?.windSpeed,
        'stale': result.isStale,
      },
    );
    if (result.data == null) throw StateError('Weather returned no data.');
    _showMessage(
      'Weather PASS · ${result.data!.temperature.toStringAsFixed(1)}°C · ${result.status.name}',
    );
  });

  Future<void> _testNotifications() => _runAction('notifications', () async {
    final count = await _diagnostics.trace<int>(
      category: DiagnosticCategory.notifications,
      operation: 'inbox_unread',
      action: () => NotificationService().unreadCount(),
    );
    _showMessage('Notification inbox PASS · unread=$count');
  });

  Future<void> _testFirebaseAnalytics() =>
      _runAction('firebase-analytics', () async {
        await FirebaseObservabilityService.instance.sendQaAnalyticsProbe();
        _diagnostics.record(
          category: DiagnosticCategory.app,
          operation: 'firebase_analytics_probe',
          message: 'PO Analytics probe submitted',
        );
        _showMessage('Analytics probe sent.');
      });

  Future<void> _testCrashlytics() =>
      _runAction('firebase-crashlytics', () async {
        await FirebaseObservabilityService.instance.sendQaCrashlyticsProbe();
        _diagnostics.record(
          category: DiagnosticCategory.app,
          operation: 'firebase_crashlytics_probe',
          message: 'PO non-fatal Crashlytics probe submitted',
        );
        _showMessage('Crashlytics non-fatal probe sent.');
      });

  Future<void> _testPerformance() =>
      _runAction('firebase-performance', () async {
        await FirebaseObservabilityService.instance.sendQaPerformanceProbe();
        _diagnostics.record(
          category: DiagnosticCategory.app,
          operation: 'firebase_performance_probe',
          message: 'PO Performance trace submitted',
        );
        _showMessage('Performance trace submitted.');
      });

  Future<void> _refreshFcm() => _runAction('firebase-fcm', () async {
    await FirebasePushService.instance.refreshAndRegisterToken();
    final push = FirebasePushService.instance.snapshot;
    if (!push.hasToken || !push.registeredWithSupabase) {
      throw StateError(
        push.lastRegistrationError ??
            'FCM token is not registered in Supabase.',
      );
    }
    _showMessage('FCM token registered: PASS');
  });

  Future<void> _copyFcmToken() async {
    final token = FirebasePushService.instance.tokenForPoTesting;
    if (token == null || token.isEmpty) {
      _showMessage('FCM token is not available yet.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    _showMessage('FCM test token copied.');
  }

  Future<void> _forceRuntimeRefresh() => _runAction('runtime', () async {
    final languageCode = Localizations.localeOf(context).languageCode;
    final result = await _diagnostics.trace(
      category: DiagnosticCategory.location,
      operation: 'force_refresh',
      action: () => ref
          .read(appRuntimeProvider.notifier)
          .forceRefresh(languageCode: languageCode),
    );
    _showMessage('Runtime refresh: ${result.status.name}');
  });

  Future<void> _clearRuntimeCaches() => _runAction('cache', () async {
    WaterService.clearCache();
    WeatherService.clearCache();
    _diagnostics.record(
      category: DiagnosticCategory.cache,
      operation: 'clear_runtime_caches',
      message: 'Water and Weather in-memory caches cleared',
    );
    _showMessage('Water + Weather cache cleared.');
  });

  Future<void> _runAction(String key, Future<void> Function() action) async {
    if (_busyAction != null) return;
    setState(() => _busyAction = key);
    try {
      await action();
    } on Object catch (error, stackTrace) {
      _diagnostics.recordError(
        category: DiagnosticCategory.app,
        operation: 'po_action_$key',
        error: error,
        stackTrace: stackTrace,
      );
      _showMessage('$key FAIL · ${error.runtimeType}: $error');
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _copyDiagnostics({
    required AppRuntimeState runtime,
    required CurrentLocationState location,
    required SelectedContext? selectedContext,
    required FluviAccessTier effectiveTier,
  }) async {
    final report = _diagnostics.exportText(
      snapshot: <String, Object?>{
        'app_version': DeveloperModePage.appVersion,
        'effective_tier': effectiveTier.name,
        'runtime_status': runtime.status.name,
        'gps_status': location.status.name,
        'selected_station': selectedContext?.stationId,
        'selected_water': selectedContext?.waterId,
        'selected_river_key': selectedContext?.riverKey,
      },
    );
    await Clipboard.setData(ClipboardData(text: report));
    _showMessage('Diagnostic report copied.');
  }

  void _showLogs() {
    final events = _diagnostics.events.reversed.toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_rounded),
                    SizedBox(width: 10),
                    Text(
                      'Recent diagnostics',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: events.isEmpty
                    ? const Center(child: Text('No diagnostic events yet.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: events.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final icon = switch (event.level) {
                            DiagnosticLevel.info => Icons.info_outline_rounded,
                            DiagnosticLevel.warning =>
                              Icons.warning_amber_rounded,
                            DiagnosticLevel.error =>
                              Icons.error_outline_rounded,
                          };
                          return ListTile(
                            dense: true,
                            leading: Icon(icon, size: 20),
                            title: Text(
                              '${event.category.name} · ${event.operation}',
                            ),
                            subtitle: SelectableText(event.toLine()),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required String keyName,
    required Future<void> Function() onTap,
  }) => ListTile(
    dense: true,
    leading: Icon(icon),
    title: Text(label),
    trailing: _busyAction == keyName
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.play_arrow_rounded),
    onTap: _busyAction == null ? onTap : null,
  );

  static Widget _info(String label, String value) => ListTile(
    dense: true,
    title: Text(label),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(
        value,
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  static Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      value,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: .7,
      ),
    ),
  );

  static String _coordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return '—';
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
