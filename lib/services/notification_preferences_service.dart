import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum NotificationCategory {
  waterAlerts('Water Alerts'),
  weatherAlerts('Weather Alerts'),
  favoriteStations('Favourite Stations'),
  communityReports('Community Reports'),
  dangerousReports('Dangerous Reports'),
  aiFishingInsights('FluviAI Radar'),
  reputationTrust('Reputation & Trust'),
  achievements('Achievements'),
  catchActivity('Catch Activity'),
  hydroDispatch('Hydro Dispatch');

  const NotificationCategory(this.label);
  final String label;
}

enum NotificationDeliveryMode { instant, digest, off }

class NotificationPreferences {
  const NotificationPreferences({
    this.enabledCategories = const {
      NotificationCategory.waterAlerts,
      NotificationCategory.weatherAlerts,
      NotificationCategory.favoriteStations,
      NotificationCategory.communityReports,
      NotificationCategory.dangerousReports,
      NotificationCategory.aiFishingInsights,
      NotificationCategory.reputationTrust,
      NotificationCategory.achievements,
      NotificationCategory.catchActivity,
      NotificationCategory.hydroDispatch,
    },
    this.inAppEnabled = true,
    this.pushEnabled = true,
    this.deliveryMode = NotificationDeliveryMode.instant,
    this.radiusKm = 25,
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 7 * 60,
    this.groupingEnabled = true,
    this.cooldown = const Duration(hours: 1),
    this.timezone = 'UTC',
  });

  final Set<NotificationCategory> enabledCategories;
  final bool inAppEnabled;
  final bool pushEnabled;
  final NotificationDeliveryMode deliveryMode;
  final int radiusKm;
  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;
  final bool groupingEnabled;
  final Duration cooldown;
  final String timezone;

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
    bool? inAppEnabled,
    bool? pushEnabled,
    NotificationDeliveryMode? deliveryMode,
    int? radiusKm,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? groupingEnabled,
    Duration? cooldown,
    String? timezone,
  }) => NotificationPreferences(
    enabledCategories: enabledCategories ?? this.enabledCategories,
    inAppEnabled: inAppEnabled ?? this.inAppEnabled,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    deliveryMode: deliveryMode ?? this.deliveryMode,
    radiusKm: radiusKm ?? this.radiusKm,
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
    quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    groupingEnabled: groupingEnabled ?? this.groupingEnabled,
    cooldown: cooldown ?? this.cooldown,
    timezone: timezone ?? this.timezone,
  );

  Map<String, dynamic> toJson() => {
    'enabled_categories': enabledCategories
        .map((category) => category.name)
        .toList(),
    'in_app_enabled': inAppEnabled,
    'push_enabled': pushEnabled,
    'delivery_mode': deliveryMode.name,
    'radius_km': radiusKm,
    'quiet_hours_enabled': quietHoursEnabled,
    'quiet_start_minutes': quietStartMinutes,
    'quiet_end_minutes': quietEndMinutes,
    'grouping_enabled': groupingEnabled,
    'cooldown_minutes': cooldown.inMinutes,
    'timezone': timezone,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['enabled_categories'];
    final enabledNames = rawCategories is List
        ? rawCategories.map((value) => value.toString()).toSet()
        : const <String>{};
    final enabled = enabledNames.isEmpty
        ? const NotificationPreferences().enabledCategories
        : NotificationCategory.values
              .where((category) => enabledNames.contains(category.name))
              .toSet();
    final deliveryName = json['delivery_mode']?.toString();
    final deliveryMode = NotificationDeliveryMode.values.firstWhere(
      (candidate) => candidate.name == deliveryName,
      orElse: () => NotificationDeliveryMode.instant,
    );
    final radius = (json['radius_km'] as num?)?.toInt() ?? 25;
    return NotificationPreferences(
      enabledCategories: enabled,
      inAppEnabled: json['in_app_enabled'] != false,
      pushEnabled: json['push_enabled'] != false,
      deliveryMode: deliveryMode,
      radiusKm: const {10, 25, 50, 100}.contains(radius) ? radius : 25,
      quietHoursEnabled: json['quiet_hours_enabled'] == true,
      quietStartMinutes: (json['quiet_start_minutes'] as num?)?.toInt() ?? 1320,
      quietEndMinutes: (json['quiet_end_minutes'] as num?)?.toInt() ?? 420,
      groupingEnabled: json['grouping_enabled'] != false,
      cooldown: Duration(
        minutes: (json['cooldown_minutes'] as num?)?.toInt() ?? 60,
      ),
      timezone: json['timezone']?.toString() ?? 'UTC',
    );
  }
}

class NotificationPreferencesService {
  NotificationPreferencesService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  static final Map<String, NotificationPreferences> _preferences = {};

  SupabaseClient? get _supabaseOrNull {
    final provided = _client;
    if (provided != null) return provided;

    try {
      return Supabase.instance.client;
    } on AssertionError {
      // Local/offline/test flows are valid before Supabase initialization.
      return null;
    }
  }

  static String _storageKey(String userId) =>
      'notification_preferences.${base64Url.encode(utf8.encode(userId))}';

  static void clearMemoryForTesting() => _preferences.clear();

  NotificationPreferences getForUser(String userId) =>
      _preferences[userId] ?? const NotificationPreferences();

  Future<NotificationPreferences> loadForUser(String userId) async {
    final supabase = _supabaseOrNull;

    if (supabase != null) {
      try {
        final rows = await supabase
            .from('notification_preferences')
            .select()
            .eq('user_id', userId)
            .limit(1);

        if (rows.isNotEmpty) {
          final value = NotificationPreferences.fromJson(
            Map<String, dynamic>.from(rows.first),
          );
          await _cache(userId, value);
          return value;
        }
      } on Exception {
        // Offline/server failure falls back to the local last-known-good.
      }
    }

    final cached = _preferences[userId];
    if (cached != null) return cached;

    final raw = (await SharedPreferences.getInstance()).getString(
      _storageKey(userId),
    );
    if (raw == null) return const NotificationPreferences();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const NotificationPreferences();
      }

      final value = NotificationPreferences.fromJson(decoded);
      _preferences[userId] = value;
      return value;
    } on FormatException {
      return const NotificationPreferences();
    }
  }

  Future<void> saveForUser(
    String userId,
    NotificationPreferences preferences,
  ) async {
    // Persist locally first so settings survive offline use and process restarts.
    await _cache(userId, preferences);

    final supabase = _supabaseOrNull;
    if (supabase == null) return;

    try {
      await supabase.from('notification_preferences').upsert({
        'user_id': userId,
        ...preferences.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Exception {
      // Local settings remain valid while remote synchronization is unavailable.
    }
  }

  Future<void> _cache(
    String userId,
    NotificationPreferences preferences,
  ) async {
    _preferences[userId] = preferences;
    final storage = await SharedPreferences.getInstance();
    await storage.setString(
      _storageKey(userId),
      jsonEncode(preferences.toJson()),
    );
  }
}
