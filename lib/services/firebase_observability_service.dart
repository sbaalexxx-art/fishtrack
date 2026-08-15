import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

import 'build_mode_service.dart';

class FirebaseObservabilitySnapshot {
  const FirebaseObservabilitySnapshot({
    required this.initialized,
    required this.collectionEnabled,
    this.projectId,
    this.lastInitializationError,
  });

  final bool initialized;
  final bool collectionEnabled;
  final String? projectId;
  final String? lastInitializationError;
}

/// Single bridge from FluviAI runtime telemetry to Firebase observability.
///
/// Supabase remains the application backend. Firebase is used only for
/// Crashlytics, Analytics, Performance and push transport.
class FirebaseObservabilityService {
  FirebaseObservabilityService._();

  static final FirebaseObservabilityService instance =
      FirebaseObservabilityService._();

  bool _initialized = false;
  bool _collectionEnabled = false;
  String? _lastInitializationError;
  FirebaseAnalyticsObserver? _navigatorObserver;

  bool get isInitialized => _initialized && Firebase.apps.isNotEmpty;
  bool get collectionEnabled => _collectionEnabled;
  FirebaseAnalyticsObserver? get navigatorObserver => _navigatorObserver;

  FirebaseObservabilitySnapshot get snapshot => FirebaseObservabilitySnapshot(
    initialized: isInitialized,
    collectionEnabled: _collectionEnabled,
    projectId: isInitialized ? Firebase.app().options.projectId : null,
    lastInitializationError: _lastInitializationError,
  );

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) {
      _lastInitializationError = 'Firebase app is not initialized.';
      return;
    }
    if (_initialized) return;

    // Public release and explicit PO builds report telemetry. Plain local debug
    // builds remain silent to avoid contaminating production dashboards.
    final enableCollection = !kDebugMode || BuildModeService.isPoInternalBuild;
    _collectionEnabled = enableCollection;

    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enableCollection,
      );
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
        enableCollection,
      );
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(
        enableCollection,
      );
      await FirebaseAnalytics.instance.setUserProperty(
        name: 'build_channel',
        value: BuildModeService.environment.replaceAll(' ', '_').toLowerCase(),
      );
      if (enableCollection) {
        await FirebaseAnalytics.instance.logAppOpen();
        _navigatorObserver ??= FirebaseAnalyticsObserver(
          analytics: FirebaseAnalytics.instance,
        );
      }
      _initialized = true;
      _lastInitializationError = null;
    } on Object catch (error) {
      _lastInitializationError = '${error.runtimeType}: $error';
    }
  }

  Future<void> setUserIdentifier(String? userId) async {
    if (!isInitialized || !_collectionEnabled) return;
    final safeId = userId?.trim() ?? '';
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(safeId);
      await FirebaseAnalytics.instance.setUserId(id: safeId.isEmpty ? null : safeId);
    } on Object {
      // Observability must never break the product runtime.
    }
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object>? parameters,
  }) async {
    if (!isInitialized || !_collectionEnabled) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: _safeEventName(name),
        parameters: parameters,
      );
    } on Object {
      // Telemetry is best effort.
    }
  }

  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!isInitialized || !_collectionEnabled) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
      );
    } on Object {
      // Never cascade an observability failure into the app.
    }
  }

  Future<void> logBreadcrumb(String message) async {
    if (!isInitialized || !_collectionEnabled) return;
    try {
      await FirebaseCrashlytics.instance.log(_sanitize(message));
    } on Object {
      // Best effort only.
    }
  }

  Future<T> trace<T>(
    String name,
    Future<T> Function() action,
  ) async {
    if (!isInitialized || !_collectionEnabled) return action();
    Trace? trace;
    try {
      trace = FirebasePerformance.instance.newTrace(_safeTraceName(name));
      await trace.start();
    } on Object {
      trace = null;
    }

    try {
      return await action();
    } finally {
      if (trace != null) {
        try {
          await trace.stop();
        } on Object {
          // Best effort only.
        }
      }
    }
  }

  Future<void> sendQaAnalyticsProbe() async {
    await logEvent(
      'po_analytics_probe',
      parameters: <String, Object>{
        'channel': BuildModeService.environment,
      },
    );
  }

  Future<void> sendQaCrashlyticsProbe() async {
    await recordError(
      StateError('FluviAI PO non-fatal Crashlytics probe'),
      StackTrace.current,
      reason: 'PO Developer Console verification',
      fatal: false,
    );
  }

  Future<void> sendQaPerformanceProbe() async {
    await trace<void>('po_performance_probe', () async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
  }

  static String _safeEventName(String value) {
    var result = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (result.isEmpty || !RegExp(r'^[a-z]').hasMatch(result)) {
      result = 'fluviai_$result';
    }
    if (result.length > 40) result = result.substring(0, 40);
    return result;
  }

  static String _safeTraceName(String value) {
    var result = value.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
    if (result.length > 90) result = result.substring(0, 90);
    return result.isEmpty ? 'fluviai_trace' : result;
  }

  static String _sanitize(String value) {
    var result = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (result.length > 500) result = '${result.substring(0, 500)}…';
    return result;
  }
}
