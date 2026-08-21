import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fishtrack/services/notification_preferences_service.dart';
import 'package:fishtrack/services/notification_service.dart';

void main() {
  group('B45C Hydro mobile runtime regression', () {
    test('Hydro Dispatch category survives preference round-trip', () {
      final preferences = NotificationPreferences.fromJson(<String, dynamic>{
        'enabled_categories': <String>['hydroDispatch'],
        'push_enabled': true,
        'in_app_enabled': true,
        'delivery_mode': 'instant',
      });

      expect(
        preferences.enabledCategories,
        contains(NotificationCategory.hydroDispatch),
      );
      expect(
        preferences.toJson()['enabled_categories'],
        contains('hydroDispatch'),
      );
    });

    test('backend Hydro notification types are parsed truthfully', () {
      const cases = <String, AppNotificationType>{
        'hydro_dispatch_forecast': AppNotificationType.hydroDispatchForecast,
        'hydro_dispatch_window_approaching':
            AppNotificationType.hydroDispatchWindowApproaching,
        'hydro_dispatch_observed': AppNotificationType.hydroDispatchObserved,
      };

      for (final entry in cases.entries) {
        expect(AppNotificationType.parse(entry.key), entry.value);
      }
    });

    test(
      'Hydro panel alert is wired to the real dispatch rule RPC service',
      () {
        final mapSource = File('lib/screens/map_page.dart').readAsStringSync();
        final serviceSource = File(
          'lib/services/hydro_dispatch_alert_service.dart',
        ).readAsStringSync();

        expect(mapSource, contains('HydroDispatchAlertService'));
        expect(mapSource, contains('_previewHydropowerPin != null'));
        expect(
          mapSource,
          contains('_hydroDispatchAlertService.enableDefaultAlerts'),
        );
        expect(
          serviceSource,
          contains("'upsert_hydro_dispatch_alert_rule_v1'"),
        );
        expect(serviceSource, contains("'p_probability_threshold': 0.70"));
        expect(serviceSource, contains("'p_notify_probability': true"));
        expect(serviceSource, contains("'p_notify_window_approaching': true"));
        expect(serviceSource, contains("'p_notify_observed_activity': true"));
      },
    );

    test('Hydro notification can navigate back to canonical map site', () {
      final centerSource = File(
        'lib/features/figma_complete/presentation/figma_account_pages.dart',
      ).readAsStringSync();
      expect(
        centerSource,
        contains("notification.entityType == 'hydropower_plant'"),
      );
      expect(centerSource, contains('HydroMapCanonicalService'));
      expect(centerSource, contains("source: 'notification-hydro-dispatch'"));
      expect(
        centerSource,
        contains('AppNotificationType.hydroDispatchForecast'),
      );
      expect(
        centerSource,
        contains('AppNotificationType.hydroDispatchObserved'),
      );
    });

    test('existing FCM and Ask Fluvi runtime wiring remains present', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final navigationSource = File(
        'lib/screens/main_navigation.dart',
      ).readAsStringSync();
      final aiSource = File(
        'lib/features/figma_complete/presentation/figma_environment_pages.dart',
      ).readAsStringSync();

      expect(
        mainSource,
        contains(
          'FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)',
        ),
      );
      expect(
        mainSource,
        contains('await FirebasePushService.instance.initialize();'),
      );
      expect(
        navigationSource,
        contains('FirebasePushService.instance.openedMessages.listen'),
      );
      expect(
        aiSource,
        contains(
          'final _answerService = const FluviDeterministicAnswerService();',
        ),
      );
      expect(aiSource, contains('_answerService.answer('));
    });
  });
}
