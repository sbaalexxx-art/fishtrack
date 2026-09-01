import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    this.deliveryAvailable,
    this.channelEnabled,
    this.lastRegistrationError,
  });

  final bool initialized;
  final String authorizationStatus;
  final bool hasToken;
  final bool registeredWithSupabase;
  final bool? deliveryAvailable;
  final bool? channelEnabled;
  final String? lastRegistrationError;
}

/// FCM is transport only. Notification truth, preferences and inbox remain in
/// Supabase.
class FirebasePushService {
  FirebasePushService._();

  static final FirebasePushService instance = FirebasePushService._();
  static const MethodChannel _nativeNotifications = MethodChannel(
    'fluviai.notifications/native',
  );

  final StreamController<RemoteMessage> _openedMessages =
      StreamController<RemoteMessage>.broadcast();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  bool _initialized = false;
  bool _registeredWithSupabase = false;
  String _authorizationStatus = 'notDetermined';
  bool? _deliveryAvailable;
  bool? _channelEnabled;
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
    deliveryAvailable: _deliveryAvailable,
    channelEnabled: _channelEnabled,
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
      await _refreshNativeDeliveryState();
      _token = await FirebaseMessaging.instance.getToken();
      await _registerCurrentToken();

      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) {
          _token = token;
          unawaited(_refreshCapabilityAndRegister());
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
        unawaited(_handleForegroundMessage(message));
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
            unawaited(_refreshCapabilityAndRegister());
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
          'delivery_available': _deliveryAvailable,
          'channel_enabled': _channelEnabled,
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
    await _refreshNativeDeliveryState();
    _token = await FirebaseMessaging.instance.getToken();
    await _registerCurrentToken();
  }

  Future<void> _refreshCapabilityAndRegister() async {
    await _refreshNativeDeliveryState();
    await _registerCurrentToken();
  }

  Future<void> _refreshNativeDeliveryState() async {
    if (!Platform.isAndroid) {
      _channelEnabled = null;
      _deliveryAvailable =
          _authorizationStatus == 'authorized' ||
          _authorizationStatus == 'provisional';
      return;
    }

    try {
      final state = await _nativeNotifications.invokeMapMethod<String, dynamic>(
        'notificationState',
      );
      _channelEnabled = state?['channelEnabled'] == true;
      _deliveryAvailable = state?['deliveryAvailable'] == true;
      if (_deliveryAvailable != true) {
        DiagnosticsService.instance.record(
          category: DiagnosticCategory.notifications,
          operation: 'notification_delivery_blocked',
          message:
              'Android notification delivery is blocked by app or channel settings',
          metadata: <String, Object?>{
            'permission': _authorizationStatus,
            'app_enabled': state?['appEnabled'],
            'channel_enabled': _channelEnabled,
          },
        );
      }
    } on MissingPluginException {
      _channelEnabled = null;
      _deliveryAvailable = _authorizationStatus == 'authorized';
    } on PlatformException catch (error, stackTrace) {
      _channelEnabled = null;
      _deliveryAvailable = null;
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'notification_state',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final eventType =
        message.data['type'] ?? message.data['event_type'] ?? 'unknown';
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.notifications,
      operation: 'fcm_foreground',
      message: 'Foreground FCM message received',
      metadata: <String, Object?>{
        'message_id': message.messageId ?? '—',
        'event_type': eventType,
      },
    );
    unawaited(
      FirebaseObservabilityService.instance.logEvent(
        'push_received_foreground',
        parameters: <String, Object>{'event_type': eventType.toString()},
      ),
    );

    if (!Platform.isAndroid) return;
    await _refreshNativeDeliveryState();
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? '';
    final body = notification?.body ?? message.data['body']?.toString() ?? '';
    final messageKey =
        message.messageId ??
        message.data['notification_id']?.toString() ??
        '${DateTime.now().microsecondsSinceEpoch}';
    final notificationId = messageKey.hashCode & 0x7fffffff;

    try {
      final displayed = await _nativeNotifications.invokeMethod<bool>(
        'showForegroundNotification',
        <String, Object>{'id': notificationId, 'title': title, 'body': body},
      );
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_foreground_display',
        message: displayed == true
            ? 'Foreground notification displayed'
            : 'Foreground notification could not be displayed',
        metadata: <String, Object?>{
          'message_id': message.messageId ?? '—',
          'event_type': eventType,
          'delivery_available': _deliveryAvailable,
          'channel_enabled': _channelEnabled,
        },
      );
    } on Object catch (error, stackTrace) {
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_foreground_display',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
        'register_notification_device_v2',
        params: <String, Object?>{
          'p_platform': Platform.isAndroid ? 'android' : 'ios',
          'p_fcm_token': token,
          'p_device_model': model,
          'p_app_version': '${package.version}+${package.buildNumber}',
          'p_locale': Platform.localeName,
          'p_latitude': null,
          'p_longitude': null,
          'p_push_authorization_status': _authorizationStatus,
          'p_notification_channel_enabled': _channelEnabled,
          'p_notification_delivery_available': _deliveryAvailable,
        },
      );
      stopwatch.stop();
      _registeredWithSupabase = true;
      _lastRegistrationError = null;
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.notifications,
        operation: 'fcm_register_device',
        message: 'FCM token and delivery capability registered with Supabase',
        duration: stopwatch.elapsed,
        metadata: <String, Object?>{
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'app_version': package.version,
          'permission': _authorizationStatus,
          'delivery_available': _deliveryAvailable,
          'channel_enabled': _channelEnabled,
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
