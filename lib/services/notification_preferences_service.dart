enum NotificationCategory {
  waterAlerts('Water Alerts'),
  favoriteStations('Favourite Stations'),
  communityReports('Community Reports'),
  dangerousReports('Dangerous Reports'),
  aiFishingInsights('FluviAI Radar'),
  reputationTrust('Reputation & Trust'),
  achievements('Achievements'),
  catchActivity('Catch Activity');

  const NotificationCategory(this.label);
  final String label;
}

class NotificationPreferences {
  const NotificationPreferences({
    this.enabledCategories = const {
      NotificationCategory.waterAlerts,
      NotificationCategory.favoriteStations,
      NotificationCategory.communityReports,
      NotificationCategory.dangerousReports,
      NotificationCategory.aiFishingInsights,
      NotificationCategory.reputationTrust,
      NotificationCategory.achievements,
      NotificationCategory.catchActivity,
    },
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 7 * 60,
    this.groupingEnabled = true,
    this.cooldown = const Duration(hours: 1),
  });

  final Set<NotificationCategory> enabledCategories;
  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;
  final bool groupingEnabled;
  final Duration cooldown;

  bool isCategoryEnabled(NotificationCategory category) =>
      enabledCategories.contains(category);

  bool isQuietAt(DateTime time) {
    if (!quietHoursEnabled) return false;
    final minute = time.toLocal().hour * 60 + time.toLocal().minute;
    if (quietStartMinutes == quietEndMinutes) return true;
    if (quietStartMinutes < quietEndMinutes) {
      return minute >= quietStartMinutes && minute < quietEndMinutes;
    }
    return minute >= quietStartMinutes || minute < quietEndMinutes;
  }

  DateTime nextQuietEnd(DateTime time) {
    final local = time.toLocal();
    var end = DateTime(
      local.year,
      local.month,
      local.day,
      quietEndMinutes ~/ 60,
      quietEndMinutes % 60,
    );
    if (!end.isAfter(local)) end = end.add(const Duration(days: 1));
    return end;
  }

  NotificationPreferences copyWith({
    Set<NotificationCategory>? enabledCategories,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? groupingEnabled,
    Duration? cooldown,
  }) => NotificationPreferences(
    enabledCategories: enabledCategories ?? this.enabledCategories,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
    quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    groupingEnabled: groupingEnabled ?? this.groupingEnabled,
    cooldown: cooldown ?? this.cooldown,
  );

  Map<String, dynamic> toJson() => {
    'enabled_categories': enabledCategories
        .map((category) => category.name)
        .toList(),
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_start_minutes': quietStartMinutes,
    'quiet_end_minutes': quietEndMinutes,
    'grouping_enabled': groupingEnabled,
    'cooldown_minutes': cooldown.inMinutes,
  };
}

class NotificationPreferencesService {
  static final Map<String, NotificationPreferences> _preferences = {};

  NotificationPreferences getForUser(String userId) =>
      _preferences[userId] ?? const NotificationPreferences();

  void saveForUser(String userId, NotificationPreferences preferences) {
    _preferences[userId] = preferences;
  }
}
