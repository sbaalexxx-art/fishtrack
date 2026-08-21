import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'build_mode_service.dart';
import 'firebase_observability_service.dart';

enum DiagnosticLevel { info, warning, error }

enum DiagnosticCategory {
  app,
  network,
  supabase,
  water,
  weather,
  community,
  notifications,
  location,
  cache,
  navigation,
  entitlement,
  ai,
}

@immutable
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.operation,
    required this.message,
    this.durationMs,
    this.metadata = const <String, String>{},
  });

  final DateTime timestamp;
  final DiagnosticLevel level;
  final DiagnosticCategory category;
  final String operation;
  final String message;
  final int? durationMs;
  final Map<String, String> metadata;

  bool get isError => level == DiagnosticLevel.error;

  String toLine() {
    final duration = durationMs == null ? '' : ' ${durationMs}ms';
    final detail = metadata.isEmpty
        ? ''
        : ' ${metadata.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}';
    return '${timestamp.toIso8601String()} ${level.name.toUpperCase()} '
        '${category.name}/$operation$duration $message$detail';
  }
}

/// Internal observability recorder for PO/QA builds.
///
/// It intentionally records metadata and status only. Request/response bodies,
/// auth tokens, API keys, image bytes and precise private payloads must never be
/// written here.
class DiagnosticsService {
  DiagnosticsService._();

  static final DiagnosticsService instance = DiagnosticsService._();
  static const int _maxEvents = 400;
  static const int _maxPersistedErrors = 50;
  static const String _persistedErrorKey = 'po_diagnostic_errors_v1';

  final List<DiagnosticEvent> _events = <DiagnosticEvent>[];
  final List<String> _persistedErrors = <String>[];
  SharedPreferences? _preferences;
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<DiagnosticEvent> get events =>
      List<DiagnosticEvent>.unmodifiable(_events);

  List<String> get persistedErrors =>
      List<String>.unmodifiable(_persistedErrors);

  List<DiagnosticEvent> get recentErrors => _events
      .where((event) => event.level == DiagnosticLevel.error)
      .toList(growable: false)
      .reversed
      .take(50)
      .toList(growable: false);

  int countFor(DiagnosticCategory category) =>
      _events.where((event) => event.category == category).length;

  Future<void> initialize(SharedPreferences preferences) async {
    if (!BuildModeService.isDeveloperVisible) return;
    _preferences = preferences;
    _persistedErrors
      ..clear()
      ..addAll(
        preferences.getStringList(_persistedErrorKey) ?? const <String>[],
      );
    for (final event in _events.where((event) => event.isError)) {
      _appendPersistedError(event.toLine());
    }
    await _flushPersistedErrors();
    revision.value++;
  }

  void clear() {
    _events.clear();
    _persistedErrors.clear();
    final preferences = _preferences;
    if (preferences != null) unawaited(preferences.remove(_persistedErrorKey));
    revision.value++;
  }

  void record({
    required DiagnosticCategory category,
    required String operation,
    required String message,
    DiagnosticLevel level = DiagnosticLevel.info,
    Duration? duration,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!BuildModeService.isDeveloperVisible) return;
    final safeMetadata = <String, String>{};
    for (final entry in metadata.entries) {
      if (_looksSensitive(entry.key)) continue;
      safeMetadata[entry.key] = _sanitize(entry.value);
    }
    final event = DiagnosticEvent(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      operation: operation,
      message: _sanitize(message),
      durationMs: duration?.inMilliseconds,
      metadata: safeMetadata,
    );
    _events.add(event);
    if (event.isError) {
      _appendPersistedError(event.toLine());
      unawaited(_flushPersistedErrors());
    }
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
    revision.value++;
  }

  void recordError({
    required DiagnosticCategory category,
    required String operation,
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object?> metadata = const <String, Object?>{},
    bool fatal = false,
  }) {
    unawaited(
      FirebaseObservabilityService.instance.recordError(
        error,
        stackTrace,
        reason: '${category.name}/$operation',
        fatal: fatal,
      ),
    );
    record(
      category: category,
      operation: operation,
      level: DiagnosticLevel.error,
      message: '${error.runtimeType}: $error',
      metadata: <String, Object?>{
        ...metadata,
        if (stackTrace != null)
          'stack': stackTrace.toString().split('\n').take(4).join(' | '),
      },
    );
  }

  Future<T> trace<T>({
    required DiagnosticCategory category,
    required String operation,
    required Future<T> Function() action,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return FirebaseObservabilityService.instance.trace<T>(
      '${category.name}_$operation',
      () async {
        if (!BuildModeService.isDeveloperVisible) return action();
        final stopwatch = Stopwatch()..start();
        record(
          category: category,
          operation: operation,
          message: 'started',
          metadata: metadata,
        );
        try {
          final result = await action();
          stopwatch.stop();
          record(
            category: category,
            operation: operation,
            message: 'completed',
            duration: stopwatch.elapsed,
            metadata: metadata,
          );
          return result;
        } on Object catch (error, stackTrace) {
          stopwatch.stop();
          recordError(
            category: category,
            operation: operation,
            error: error,
            stackTrace: stackTrace,
            metadata: <String, Object?>{
              ...metadata,
              'duration_ms': stopwatch.elapsedMilliseconds,
            },
          );
          rethrow;
        }
      },
    );
  }

  String exportText({
    Map<String, Object?> snapshot = const <String, Object?>{},
  }) {
    final buffer = StringBuffer()
      ..writeln('FluviAI PO Diagnostics')
      ..writeln('generated_at=${DateTime.now().toIso8601String()}')
      ..writeln('environment=${BuildModeService.environment}');
    for (final entry in snapshot.entries) {
      if (_looksSensitive(entry.key)) continue;
      buffer.writeln('${entry.key}=${_sanitize(entry.value)}');
    }
    buffer.writeln('--- events (${_events.length}) ---');
    for (final event in _events) {
      buffer.writeln(event.toLine());
    }
    if (_persistedErrors.isNotEmpty) {
      buffer.writeln('--- persisted errors (${_persistedErrors.length}) ---');
      for (final line in _persistedErrors) {
        buffer.writeln(line);
      }
    }
    return buffer.toString();
  }

  void _appendPersistedError(String line) {
    if (_persistedErrors.isNotEmpty && _persistedErrors.last == line) return;
    _persistedErrors.add(_sanitize(line));
    if (_persistedErrors.length > _maxPersistedErrors) {
      _persistedErrors.removeRange(
        0,
        _persistedErrors.length - _maxPersistedErrors,
      );
    }
  }

  Future<void> _flushPersistedErrors() async {
    final preferences = _preferences;
    if (preferences == null) return;
    await preferences.setStringList(
      _persistedErrorKey,
      List<String>.unmodifiable(_persistedErrors),
    );
  }

  static bool _looksSensitive(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('password') ||
        normalized.contains('authorization') ||
        normalized.contains('api_key') ||
        normalized.contains('apikey');
  }

  static String _sanitize(Object? value) {
    if (value == null) return 'null';
    var text = value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (text.length > 500) text = '${text.substring(0, 500)}…';
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/]+=*', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    return text;
  }
}
