import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/l10n.dart';
import '../services/notification_preferences_service.dart';
import '../features/figma_complete/presentation/figma_foundation.dart';

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  final _service = NotificationPreferencesService();
  late NotificationPreferences _preferences;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _preferences = _userId == null
        ? const NotificationPreferences()
        : _service.getForUser(_userId!);
    final userId = _userId;
    if (userId != null) unawaited(_load(userId));
  }

  Future<void> _load(String userId) async {
    final loaded = await _service.loadForUser(userId);
    if (!mounted || _userId != userId) return;
    setState(() => _preferences = loaded);
  }

  void _save(NotificationPreferences value) {
    final userId = _userId;
    if (userId == null) return;
    unawaited(_service.saveForUser(userId, value));
    setState(() => _preferences = value);
  }

  Future<void> _pickTime({required bool start}) async {
    final minutes = start
        ? _preferences.quietStartMinutes
        : _preferences.quietEndMinutes;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (selected == null) return;
    final value = selected.hour * 60 + selected.minute;
    _save(
      start
          ? _preferences.copyWith(quietStartMinutes: value)
          : _preferences.copyWith(quietEndMinutes: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return FigmaCanonicalScaffold(
        key: const ValueKey('notification-preferences-page'),
        title: context.l10n.notificationPreferences,
        child: Center(
          child: Text(context.l10n.signInForNotificationPreferences),
        ),
      );
    }
    return FigmaCanonicalScaffold(
      key: const ValueKey('notification-preferences-page'),
      title: context.l10n.notificationPreferences,
      padding: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Text('Livrare', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            value: _preferences.inAppEnabled,
            title: const Text('Notificări în aplicație'),
            subtitle: const Text('Păstrează evenimentele în centrul FluviAI.'),
            onChanged: (value) =>
                _save(_preferences.copyWith(inAppEnabled: value)),
          ),
          SwitchListTile(
            value: _preferences.pushEnabled,
            title: const Text('Notificări push'),
            subtitle: const Text(
              'Primește alerte și când FluviAI este în fundal sau închisă.',
            ),
            onChanged: (value) =>
                _save(_preferences.copyWith(pushEnabled: value)),
          ),
          ListTile(
            title: const Text('Mod de livrare'),
            trailing: DropdownButton<NotificationDeliveryMode>(
              value: _preferences.deliveryMode,
              items: NotificationDeliveryMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(switch (mode) {
                        NotificationDeliveryMode.instant => 'Instant',
                        NotificationDeliveryMode.digest => 'Digest',
                        NotificationDeliveryMode.off => 'Oprit',
                      }),
                    ),
                  )
                  .toList(),
              onChanged: (mode) {
                if (mode != null) {
                  _save(_preferences.copyWith(deliveryMode: mode));
                }
              },
            ),
          ),
          ListTile(
            title: const Text('Rază alerte'),
            subtitle: const Text(
              'Folosită pentru rapoarte și capturi din apropiere.',
            ),
            trailing: DropdownButton<int>(
              value: _preferences.radiusKm,
              items: const [10, 25, 50, 100]
                  .map(
                    (km) => DropdownMenuItem(value: km, child: Text('$km km')),
                  )
                  .toList(),
              onChanged: (km) {
                if (km != null) {
                  _save(_preferences.copyWith(radiusKm: km));
                }
              },
            ),
          ),
          const Divider(),
          Text(
            context.l10n.categories,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final category in NotificationCategory.values)
            SwitchListTile(
              value: _preferences.isCategoryEnabled(category),
              title: Text(_categoryLabel(context, category)),
              onChanged: (enabled) {
                final categories = {..._preferences.enabledCategories};
                enabled
                    ? categories.add(category)
                    : categories.remove(category);
                _save(_preferences.copyWith(enabledCategories: categories));
              },
            ),
          const Divider(),
          Text(
            context.l10n.priority,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ListTile(
            leading: Icon(Icons.notifications_off_outlined),
            title: Text(context.l10n.notificationPrioritySilent),
            subtitle: Text(context.l10n.notificationPrioritySilentDescription),
          ),
          ListTile(
            leading: Icon(Icons.notifications_active_outlined),
            title: Text(context.l10n.notificationPriorityImportant),
            subtitle: Text(
              context.l10n.notificationPriorityImportantDescription,
            ),
          ),
          ListTile(
            leading: Icon(Icons.warning_amber_rounded),
            title: Text(context.l10n.notificationPriorityCritical),
            subtitle: Text(
              context.l10n.notificationPriorityCriticalDescription,
            ),
          ),
          const Divider(),
          SwitchListTile(
            value: _preferences.quietHoursEnabled,
            title: Text(context.l10n.quietHours),
            onChanged: (value) =>
                _save(_preferences.copyWith(quietHoursEnabled: value)),
          ),
          ListTile(
            enabled: _preferences.quietHoursEnabled,
            title: Text(context.l10n.startTime),
            trailing: Text(_time(_preferences.quietStartMinutes)),
            onTap: _preferences.quietHoursEnabled
                ? () => _pickTime(start: true)
                : null,
          ),
          ListTile(
            enabled: _preferences.quietHoursEnabled,
            title: Text(context.l10n.endTime),
            trailing: Text(_time(_preferences.quietEndMinutes)),
            onTap: _preferences.quietHoursEnabled
                ? () => _pickTime(start: false)
                : null,
          ),
          const Divider(),
          SwitchListTile(
            value: _preferences.groupingEnabled,
            title: Text(context.l10n.groupSimilarNotifications),
            subtitle: Text(context.l10n.notificationGroupingDescription),
            onChanged: (value) =>
                _save(_preferences.copyWith(groupingEnabled: value)),
          ),
          ListTile(
            title: Text(context.l10n.duplicateCooldown),
            trailing: DropdownButton<int>(
              value: _preferences.cooldown.inMinutes,
              items: const [15, 30, 60, 120]
                  .map(
                    (minutes) => DropdownMenuItem(
                      value: minutes,
                      child: Text('$minutes min'),
                    ),
                  )
                  .toList(),
              onChanged: (minutes) {
                if (minutes != null) {
                  _save(
                    _preferences.copyWith(cooldown: Duration(minutes: minutes)),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(
    BuildContext context,
    NotificationCategory category,
  ) {
    final l10n = context.l10n;
    return switch (category) {
      NotificationCategory.waterAlerts => l10n.notificationWaterAlerts,
      NotificationCategory.weatherAlerts => l10n.notificationWeatherAlerts,
      NotificationCategory.favoriteStations =>
        l10n.notificationFavouriteStations,
      NotificationCategory.communityReports =>
        l10n.notificationCommunityReports,
      NotificationCategory.dangerousReports =>
        l10n.notificationDangerousReports,
      NotificationCategory.aiFishingInsights => l10n.notificationFluviAiRadar,
      NotificationCategory.reputationTrust => l10n.notificationReputationTrust,
      NotificationCategory.achievements => l10n.notificationAchievements,
      NotificationCategory.catchActivity => l10n.notificationCatchActivity,
    };
  }

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}
