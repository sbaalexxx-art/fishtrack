import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'diagnostics_service.dart';
import 'firebase_observability_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

class FirebasePushSnapshot {
  const FirebasePushSnapshot({
    required this.initialized,
    required this.authorizationStatus,
    required this.hasToken,
    required this.registeredWithSupabase,
    this.lastRegistrationError,
  });

  final bool initialized;
  final String authorizationStatus;
  final bool hasToken;
  final bool registeredWithSupabase;
  final String? lastRegistrationError;
}

/// FCM is transport only. Notification truth, preferences and inbox remain in
/// Supabase.
class FirebasePushService {
  FirebasePushService._();

  static final FirebasePushService instance = FirebasePushService._();

  final StreamController<RemoteMessage> _openedMessages =
      StreamController<RemoteMessage>.broadcast();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  bool _initialized = false;
  bool _registeredWithSupabase = false;
  String _authorizationStatus = 'notDetermined';
  String? _token;
  String? _lastRegistrationError;
  RemoteMessage? _pendingOpenedMessage;

  Stream<RemoteMessage> get openedMessages => _openedMessages.stream;
  String? get tokenForPoTesting => _token;

  RemoteMessage? takePendingOpenedMessage() {
    final message = _pendingOpenedMessage;
    _pendingOpenedMessage = null;
    return message;
  }

  FirebasePushSnapshot get snapshot => FirebasePushSnapshot(
    initialized: _initialized,
    authorizationStatus: _authorizationStatus,
    hasToken: _token?.isNotEmpty == true,
    registeredWithSupabase: _registeredWithSupabase,
    lastRegistrationError: _lastRegistrationError,
  );

  Future<void> initialize() async {
    if (_initialized || Firebase.apps.isEmpty || kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _authorizationStatus = settings.authorizationStatus.name;
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      _token = await FirebaseMessaging.instance.getToken();
      await _registerCurrentToken();

      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) {
          _token = token;
          unawaited(_registerCurrentToken());
        },
        onError: (Object error, StackTrace stackTrace) {
          DiagnosticsService.instance.recordError(
            category: DiagnosticCategory.notifications,
            operation: 'fcm_token_refresh',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );

      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) {
        DiagnosticsService.instance.record(
          category: DiagnosticCategory.notifications,
          operation: 'fcm_foreground',
          message: 'Foreground FCM message received',
          metadata: <String, Object?>{
            'message_id': message.messageId ?? '—',
            'event_type':
                message.data['type'] ?? message.data['event_type'] ?? '—',
          },
        );
        unawaited(
          FirebaseObservabilityService.instance.logEvent(
            'push_received_foreground',
            parameters: <String, Object>{
              'event_type':
                  (message.data['type'] ??
                          message.data['event_type'] ??
                          'unknown')
                      .toString(),
            },
          ),
        );
      });

      _openSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );

      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            final userId = state.session?.user.id;
            unawaited(
              FirebaseObservabilityService.instance.setUserIdentifier(userId),
            );
            if (state.session == null) {
              _registeredWithSupabase = false;
              return;
            }
            unawaited(_registerCurrentToken());
          });

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _pendingOpenedMessage = initial;
      }
      _initialized = true;
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_initialize',
        message: 'Firebase Messaging initialized',
        metadata: <String, Object?>{
          'permission': _authorizationStatus,
          'has_token': _token?.isNotEmpty == true,
          'registered': _registeredWithSupabase,
        },
      );
    } on Object catch (error, stackTrace) {
      _lastRegistrationError = '${error.runtimeType}: $error';
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_initialize',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> refreshAndRegisterToken() async {
    if (Firebase.apps.isEmpty) return;
    _token = await FirebaseMessaging.instance.getToken();
    await _registerCurrentToken();
  }

  Future<void> _registerCurrentToken() async {
    final token = _token;
    final session = Supabase.instance.client.auth.currentSession;
    if (token == null || token.isEmpty || session == null) {
      _registeredWithSupabase = false;
      return;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final package = await PackageInfo.fromPlatform();
      String? model;
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        model = '${info.manufacturer} ${info.model}'.trim();
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        model = info.utsname.machine;
      }

      await Supabase.instance.client.rpc(
        'register_notification_device_v1',
        params: <String, Object?>{
          'p_platform': Platform.isAndroid ? 'android' : 'ios',
          'p_fcm_token': token,
          'p_device_model': model,
          'p_app_version': '${package.version}+${package.buildNumber}',
          'p_locale': Platform.localeName,
          'p_latitude': null,
          'p_longitude': null,
        },
      );
      stopwatch.stop();
      _registeredWithSupabase = true;
      _lastRegistrationError = null;
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_register_device',
        message: 'FCM token registered with Supabase',
        duration: stopwatch.elapsed,
        metadata: <String, Object?>{
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'app_version': package.version,
        },
      );
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      _registeredWithSupabase = false;
      _lastRegistrationError = '${error.runtimeType}: $error';
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_register_device',
        error: error,
        stackTrace: stackTrace,
        metadata: <String, Object?>{
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );
    }
  }

  void _handleOpenedMessage(RemoteMessage message) {
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.notifications,
      operation: 'fcm_open',
      message: 'Notification opened application',
      metadata: <String, Object?>{
        'message_id': message.messageId ?? '—',
        'event_type': message.data['type'] ?? message.data['event_type'] ?? '—',
      },
    );
    unawaited(
      FirebaseObservabilityService.instance.logEvent(
        'push_opened',
        parameters: <String, Object>{
          'event_type':
              (message.data['type'] ?? message.data['event_type'] ?? 'unknown')
                  .toString(),
        },
      ),
    );
    _openedMessages.add(message);
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openSubscription?.cancel();
    await _authSubscription?.cancel();
    await _openedMessages.close();
  }
}
