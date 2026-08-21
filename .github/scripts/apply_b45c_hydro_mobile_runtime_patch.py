from pathlib import Path

PREFS = Path('lib/services/notification_preferences_service.dart')
PREFS_PAGE = Path('lib/screens/notification_preferences_page.dart')
NOTIFICATIONS = Path('lib/services/notification_service.dart')
ACCOUNT = Path('lib/features/figma_complete/presentation/figma_account_pages.dart')
MAP = Path('lib/screens/map_page.dart')
ALERT_SERVICE = Path('lib/services/hydro_dispatch_alert_service.dart')
TEST = Path('test/b45c_hydro_mobile_runtime_regression_test.dart')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'ABORT {label}: expected exactly 1 anchor, found {count}')
    return text.replace(old, new, 1)


def read(path: Path) -> str:
    if not path.exists():
        raise SystemExit(f'ABORT missing protected source: {path}')
    return path.read_text(encoding='utf-8')


prefs = read(PREFS)
prefs_page = read(PREFS_PAGE)
notifications = read(NOTIFICATIONS)
account = read(ACCOUNT)
map_text = read(MAP)

# Idempotent validated state. A partial state is never accepted.
marker = "hydroDispatch('Hydro Dispatch')"
if marker in prefs:
    required = {
        PREFS: [marker, 'NotificationCategory.hydroDispatch,'],
        PREFS_PAGE: ['NotificationCategory.hydroDispatch'],
        NOTIFICATIONS: [
            "hydroDispatchForecast('hydro_dispatch_forecast')",
            "hydroDispatchWindowApproaching('hydro_dispatch_window_approaching')",
            "hydroDispatchObserved('hydro_dispatch_observed')",
            'NotificationCategory.hydroDispatch',
        ],
        ACCOUNT: [
            "notification.entityType == 'hydropower_plant'",
            'HydroMapCanonicalService',
            "source: 'notification-hydro-dispatch'",
        ],
        MAP: [
            'HydroDispatchAlertService',
            '_previewHydropowerPin != null',
            '_hydroDispatchAlertService.enableDefaultAlerts',
        ],
    }
    for path, tokens in required.items():
        text = read(path)
        for token in tokens:
            if token not in text:
                raise SystemExit(f'ABORT partial Hydro mobile runtime state: {path} missing {token}')
    if not ALERT_SERVICE.exists() or not TEST.exists():
        raise SystemExit('ABORT partial Hydro mobile runtime state: service/test missing')
    print('B45C Hydro mobile runtime integration already present and internally consistent.')
    raise SystemExit(0)

# Guard the exact B45C runtime shapes before any write.
for required in (
    "catchActivity('Catch Activity');",
    'NotificationCategory.catchActivity,',
    "this.timezone = 'UTC'",
):
    if required not in prefs:
        raise SystemExit(f'ABORT notification preference guard missing: {required}')

for required in (
    'NotificationCategory.catchActivity => l10n.notificationCatchActivity,',
    'for (final category in NotificationCategory.values)',
):
    if required not in prefs_page:
        raise SystemExit(f'ABORT preference UI guard missing: {required}')

for required in (
    "catchLiked('catch_liked');",
    'AppNotificationType.weatherAlert => NotificationCategory.weatherAlerts,',
    'static NotificationCategory _categoryFor(AppNotificationType type)',
):
    if required not in notifications:
        raise SystemExit(f'ABORT notification model guard missing: {required}')

for required in (
    "import '../../../core/navigation/map_entry.dart';",
    "import '../../../services/notification_service.dart';",
    'final stationId = notification.relatedStation;',
    'AppNotificationType.catchLiked => true,',
    'AppNotificationType.catchLiked => Icons.favorite_border_rounded,',
):
    if required not in account:
        raise SystemExit(f'ABORT notification center guard missing: {required}')

for required in (
    "import '../services/hydro_map_canonical_service.dart';",
    'final HydroMapCanonicalService _hydroMapCanonicalService =',
    'bool get _hasHydroAlertTarget {',
    'Future<void> _openHydroAlert() async {',
):
    if required not in map_text:
        raise SystemExit(f'ABORT Hydro map alert guard missing: {required}')

# 1) Preserve Hydro Dispatch notification category through mobile load/save.
prefs = replace_once(
    prefs,
    "  catchActivity('Catch Activity');",
    "  catchActivity('Catch Activity'),\n  hydroDispatch('Hydro Dispatch');",
    'Hydro notification category enum',
)
prefs = replace_once(
    prefs,
    '      NotificationCategory.catchActivity,\n    },',
    '      NotificationCategory.catchActivity,\n      NotificationCategory.hydroDispatch,\n    },',
    'Hydro notification category default',
)

prefs_page = replace_once(
    prefs_page,
    '      NotificationCategory.catchActivity => l10n.notificationCatchActivity,\n    };',
    "      NotificationCategory.catchActivity => l10n.notificationCatchActivity,\n      NotificationCategory.hydroDispatch => 'Hydro Dispatch',\n    };",
    'Hydro notification preference label',
)

# 2) Parse backend Hydro notification types without lying as water alerts.
notifications = replace_once(
    notifications,
    "  catchLiked('catch_liked');",
    "  catchLiked('catch_liked'),\n"
    "  hydroDispatchForecast('hydro_dispatch_forecast'),\n"
    "  hydroDispatchWindowApproaching('hydro_dispatch_window_approaching'),\n"
    "  hydroDispatchObserved('hydro_dispatch_observed');",
    'Hydro notification types',
)
notifications = replace_once(
    notifications,
    '        AppNotificationType.weatherAlert => NotificationCategory.weatherAlerts,',
    '        AppNotificationType.weatherAlert => NotificationCategory.weatherAlerts,\n'
    '        AppNotificationType.hydroDispatchForecast ||\n'
    '        AppNotificationType.hydroDispatchWindowApproaching ||\n'
    '        AppNotificationType.hydroDispatchObserved =>\n'
    '          NotificationCategory.hydroDispatch,',
    'Hydro notification category mapping',
)

# 3) Notification Center: surface Hydro events and return to the canonical site.
account = replace_once(
    account,
    "import '../../../core/navigation/map_entry.dart';",
    "import '../../../core/navigation/map_entry.dart';\n"
    "import '../../../core/map/pending_map_camera.dart';",
    'notification center map target import',
)
account = replace_once(
    account,
    "import '../../../services/notification_service.dart';",
    "import '../../../services/notification_service.dart';\n"
    "import '../../../services/hydro_map_canonical_service.dart';",
    'notification center Hydro service import',
)
account = replace_once(
    account,
    '            AppNotificationType.catchLiked => true,',
    '            AppNotificationType.catchLiked ||\n'
    '            AppNotificationType.hydroDispatchForecast ||\n'
    '            AppNotificationType.hydroDispatchWindowApproaching ||\n'
    '            AppNotificationType.hydroDispatchObserved => true,',
    'notification center Hydro alert filter',
)
account = replace_once(
    account,
    '    AppNotificationType.catchLiked => Icons.favorite_border_rounded,',
    '    AppNotificationType.catchLiked => Icons.favorite_border_rounded,\n'
    '    AppNotificationType.hydroDispatchForecast ||\n'
    '    AppNotificationType.hydroDispatchWindowApproaching ||\n'
    '    AppNotificationType.hydroDispatchObserved => Icons.bolt_rounded,',
    'notification center Hydro icon',
)
account = replace_once(
    account,
    '      final stationId = notification.relatedStation;',
    "      final notificationEntityId = notification.entityId;\n"
    "      if (notification.entityType == 'hydropower_plant' &&\n"
    "          notificationEntityId != null &&\n"
    "          notificationEntityId.isNotEmpty) {\n"
    "        final sites = await const HydroMapCanonicalService().getVerifiedSites(\n"
    "          countryCode: 'RO',\n"
    "        );\n"
    "        HydroCanonicalMapSite? site;\n"
    "        for (final candidate in sites) {\n"
    "          if (candidate.plantId == notificationEntityId) {\n"
    "            site = candidate;\n"
    "            break;\n"
    "          }\n"
    "        }\n"
    "        if (!mounted) return;\n"
    "        if (site != null) {\n"
    "          await AppNavigator.open<void>(\n"
    "            context,\n"
    "            AppDestination.contextualMap,\n"
    "            arguments: ContextualMapEntry.forTarget(\n"
    "              source: 'notification-hydro-dispatch',\n"
    "              target: RuntimeMapCameraTarget(\n"
    "                source: 'notification-hydro-dispatch',\n"
    "                entityId: site.plantId!,\n"
    "                latitude: site.latitude,\n"
    "                longitude: site.longitude,\n"
    "                zoom: 13.4,\n"
    "              ),\n"
    "            ),\n"
    "          );\n"
    "          return;\n"
    "        }\n"
    "      }\n\n"
    "      final stationId = notification.relatedStation;",
    'notification center Hydro deep link',
)

# 4) Existing Hydro panel Alert button becomes a real Hydro Dispatch rule action.
map_text = replace_once(
    map_text,
    "import '../services/hydro_map_canonical_service.dart';",
    "import '../services/hydro_map_canonical_service.dart';\n"
    "import '../services/hydro_dispatch_alert_service.dart';",
    'Hydro dispatch alert service import',
)
map_text = replace_once(
    map_text,
    '  final HydroMapCanonicalService _hydroMapCanonicalService =\n      const HydroMapCanonicalService();',
    '  final HydroMapCanonicalService _hydroMapCanonicalService =\n'
    '      const HydroMapCanonicalService();\n'
    '  final HydroDispatchAlertService _hydroDispatchAlertService =\n'
    '      const HydroDispatchAlertService();',
    'Hydro dispatch alert service field',
)
map_text = replace_once(
    map_text,
    '  bool get _hasHydroAlertTarget {\n    if (_previewStation != null || _previewWaterAsset != null) return true;',
    '  bool get _hasHydroAlertTarget {\n'
    '    if (_previewHydropowerPin != null) return true;\n'
    '    if (_previewStation != null || _previewWaterAsset != null) return true;',
    'Hydro plant alert target',
)
map_text = replace_once(
    map_text,
    '  Future<void> _openHydroAlert() async {\n    Object? arguments;',
    "  Future<void> _openHydroAlert() async {\n"
    "    if (_previewHydropowerPin case final plant?) {\n"
    "      try {\n"
    "        await _hydroDispatchAlertService.enableDefaultAlerts(plant.entityId);\n"
    "        if (!mounted) return;\n"
    "        ScaffoldMessenger.of(context).showSnackBar(\n"
    "          SnackBar(\n"
    "            content: Text(\n"
    "              Localizations.localeOf(context).languageCode.toLowerCase() == 'ro'\n"
    "                  ? 'Alerte Hydro activate pentru ${plant.name}: probabilitate ≥70%, fereastră estimată și observații.'\n"
    "                  : 'Hydro alerts enabled for ${plant.name}: probability ≥70%, estimated window and observations.',\n"
    "            ),\n"
    "          ),\n"
    "        );\n"
    "      } on HydroDispatchAlertException catch (error) {\n"
    "        if (!mounted) return;\n"
    "        ScaffoldMessenger.of(context).showSnackBar(\n"
    "          SnackBar(content: Text(error.message)),\n"
    "        );\n"
    "      }\n"
    "      return;\n"
    "    }\n\n"
    "    Object? arguments;",
    'Hydro plant alert action',
)

alert_service = r'''import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class HydroDispatchAlertService {
  const HydroDispatchAlertService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<void> enableDefaultAlerts(String plantId) async {
    final normalized = plantId.trim();
    if (normalized.isEmpty) {
      throw const HydroDispatchAlertException('Hydro plant identity is missing.');
    }

    try {
      await _supabase
          .rpc(
            'upsert_hydro_dispatch_alert_rule_v1',
            params: <String, Object?>{
              'p_plant_id': normalized,
              'p_probability_threshold': 0.70,
              'p_min_probability_delta': 0.08,
              'p_window_lead_minutes': 90,
              'p_cooldown_minutes': 90,
              'p_notify_probability': true,
              'p_notify_window_approaching': true,
              'p_notify_observed_activity': true,
              'p_enabled': true,
              // Favorite state has its own explicit control in the Hydro panel.
              'p_save_favorite': false,
            },
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException {
      throw const HydroDispatchAlertException('No internet connection.');
    } on TimeoutException {
      throw const HydroDispatchAlertException(
        'Hydro alert request timed out. Please retry.',
      );
    } on PostgrestException catch (error) {
      throw HydroDispatchAlertException(
        error.message.trim().isEmpty
            ? 'Hydro alerts are unavailable. Please retry.'
            : error.message,
      );
    }
  }
}

class HydroDispatchAlertException implements Exception {
  const HydroDispatchAlertException(this.message);

  final String message;

  @override
  String toString() => message;
}
'''

regression_test = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fishtrack/services/notification_preferences_service.dart';
import 'package:fishtrack/services/notification_service.dart';

void main() {
  group('B45C Hydro mobile runtime regression', () {
    test('Hydro Dispatch category survives preference round-trip', () {
      final preferences = NotificationPreferences.fromJson(
        <String, dynamic>{
          'enabled_categories': <String>['hydroDispatch'],
          'push_enabled': true,
          'in_app_enabled': true,
          'delivery_mode': 'instant',
        },
      );

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

    test('Hydro panel alert is wired to the real dispatch rule RPC service', () {
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
    });

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
      expect(centerSource, contains('AppNotificationType.hydroDispatchForecast'));
      expect(centerSource, contains('AppNotificationType.hydroDispatchObserved'));
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
        contains('final _answerService = const FluviDeterministicAnswerService();'),
      );
      expect(aiSource, contains('_answerService.answer('));
    });
  });
}
'''

if ALERT_SERVICE.exists() or TEST.exists():
    raise SystemExit('ABORT unexpected pre-existing Hydro mobile runtime service/test')

# Strict postconditions before writes.
for text, tokens, label in (
    (prefs, [marker, 'NotificationCategory.hydroDispatch,'], 'preferences'),
    (prefs_page, ['NotificationCategory.hydroDispatch'], 'preferences UI'),
    (
        notifications,
        [
            "hydroDispatchForecast('hydro_dispatch_forecast')",
            "hydroDispatchWindowApproaching('hydro_dispatch_window_approaching')",
            "hydroDispatchObserved('hydro_dispatch_observed')",
            'NotificationCategory.hydroDispatch',
        ],
        'notification model',
    ),
    (
        account,
        [
            "notification.entityType == 'hydropower_plant'",
            "source: 'notification-hydro-dispatch'",
            'HydroMapCanonicalService',
        ],
        'notification center',
    ),
    (
        map_text,
        [
            'HydroDispatchAlertService',
            '_previewHydropowerPin != null',
            '_hydroDispatchAlertService.enableDefaultAlerts',
        ],
        'Hydro map',
    ),
):
    for token in tokens:
        if token not in text:
            raise SystemExit(f'ABORT postcondition {label} missing: {token}')

PREFS.write_text(prefs, encoding='utf-8')
PREFS_PAGE.write_text(prefs_page, encoding='utf-8')
NOTIFICATIONS.write_text(notifications, encoding='utf-8')
ACCOUNT.write_text(account, encoding='utf-8')
MAP.write_text(map_text, encoding='utf-8')
ALERT_SERVICE.write_text(alert_service, encoding='utf-8')
TEST.write_text(regression_test, encoding='utf-8')

print('B45C Hydro mobile notification/AI runtime integration applied with strict guards.')
