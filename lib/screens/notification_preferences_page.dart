import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/l10n.dart';
import '../services/notification_preferences_service.dart';

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
  }

  void _save(NotificationPreferences value) {
    final userId = _userId;
    if (userId == null) return;
    _service.saveForUser(userId, value);
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
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.notificationPreferences)),
        body: Center(
          child: Text(context.l10n.signInForNotificationPreferences),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.notificationPreferences)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(context.l10n.categories, style: Theme.of(context).textTheme.titleLarge),
          for (final category in NotificationCategory.values)
            SwitchListTile(
              value: _preferences.isCategoryEnabled(category),
              title: Text(category.label),
              onChanged: (enabled) {
                final categories = {..._preferences.enabledCategories};
                enabled
                    ? categories.add(category)
                    : categories.remove(category);
                _save(_preferences.copyWith(enabledCategories: categories));
              },
            ),
          const Divider(),
          Text(context.l10n.priority, style: Theme.of(context).textTheme.titleLarge),
          const ListTile(
            leading: Icon(Icons.notifications_off_outlined),
            title: Text('Silent'),
            subtitle: Text('Stored only; no popup.'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('Important'),
            subtitle: Text('Normal delivery and respects quiet hours.'),
          ),
          const ListTile(
            leading: Icon(Icons.warning_amber_rounded),
            title: Text('Critical'),
            subtitle: Text('Delivered immediately, including quiet hours.'),
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
            subtitle: const Text(
              'Groups station and event type within 30 minutes.',
            ),
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

  static String _time(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}
