import 'package:supabase_flutter/supabase_flutter.dart';

import 'favorite_stations_service.dart';
import 'notification_preferences_service.dart';
import 'reputation_service.dart';
import 'water_alert_service.dart';
import 'water_service.dart';

enum AppNotificationType {
  waterLevelChanged('water_level_changed'),
  waterTrendChanged('water_trend_changed'),
  newReportNearFavoriteStation('new_report_near_favorite_station'),
  dangerousReport('dangerous_report'),
  reputationIncreased('reputation_increased'),
  trustBadgeUpgraded('trust_badge_upgraded'),
  favoriteStationUpdate('favorite_station_update');

  const AppNotificationType(this.databaseValue);
  final String databaseValue;

  static AppNotificationType parse(Object? value) => values.firstWhere(
    (type) => type.databaseValue == value,
    orElse: () => waterLevelChanged,
  );
}

enum NotificationPriority {
  silent,
  important,
  critical;

  static NotificationPriority parse(Object? value) => switch (value) {
    'silent' || 'low' => silent,
    'critical' => critical,
    'important' || 'normal' || 'high' => important,
    _ => important,
  };
}

enum NotificationDelivery { storedOnly, deliver, postponed }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.priority,
    this.delivery = NotificationDelivery.deliver,
    this.deliverAfter,
    this.groupCount = 1,
    this.relatedStation,
    this.relatedReport,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        type: AppNotificationType.parse(json['type']),
        relatedStation: json['related_station']?.toString(),
        relatedReport: json['related_report']?.toString(),
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        isRead: json['read'] == true,
        priority: NotificationPriority.parse(json['priority']),
        delivery: NotificationDelivery.values.firstWhere(
          (delivery) => delivery.name == json['delivery'],
          orElse: () => NotificationDelivery.deliver,
        ),
        deliverAfter: DateTime.tryParse(
          json['deliver_after']?.toString() ?? '',
        ),
        groupCount: json['group_count'] is num
            ? (json['group_count'] as num).toInt()
            : 1,
      );

  final String id;
  final String userId;
  final String title;
  final String message;
  final AppNotificationType type;
  final String? relatedStation;
  final String? relatedReport;
  final DateTime createdAt;
  final bool isRead;
  final NotificationPriority priority;
  final NotificationDelivery delivery;
  final DateTime? deliverAfter;
  final int groupCount;

  AppNotification copyWith({
    bool? isRead,
    String? message,
    DateTime? createdAt,
    NotificationDelivery? delivery,
    DateTime? deliverAfter,
    int? groupCount,
  }) => AppNotification(
    id: id,
    userId: userId,
    title: title,
    message: message ?? this.message,
    type: type,
    relatedStation: relatedStation,
    relatedReport: relatedReport,
    createdAt: createdAt ?? this.createdAt,
    isRead: isRead ?? this.isRead,
    priority: priority,
    delivery: delivery ?? this.delivery,
    deliverAfter: deliverAfter ?? this.deliverAfter,
    groupCount: groupCount ?? this.groupCount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'message': message,
    'type': type.databaseValue,
    'related_station': relatedStation,
    'related_report': relatedReport,
    'created_at': createdAt.toUtc().toIso8601String(),
    'read': isRead,
    'priority': priority.name,
    'delivery': delivery.name,
    'deliver_after': deliverAfter?.toUtc().toIso8601String(),
    'group_count': groupCount,
  };
}

abstract interface class NotificationStore {
  List<AppNotification> forUser(String userId);
  void add(AppNotification notification);
  void upsert(AppNotification notification);
  void markAsRead(String userId, String notificationId);
  void clearRead(String userId);
}

class MemoryNotificationStore implements NotificationStore {
  MemoryNotificationStore({this.maximumNotifications = 100});

  final int maximumNotifications;
  final List<AppNotification> _items = [];
  final Set<String> _ids = {};

  @override
  List<AppNotification> forUser(String userId) =>
      List.unmodifiable(_items.where((item) => item.userId == userId));

  @override
  void add(AppNotification notification) {
    if (!_ids.add(notification.id)) return;
    _items.insert(0, notification);
    if (_items.length > maximumNotifications) {
      _ids.remove(_items.removeLast().id);
    }
  }

  @override
  void upsert(AppNotification notification) {
    final index = _items.indexWhere((item) => item.id == notification.id);
    if (index < 0) {
      add(notification);
      return;
    }
    _items[index] = notification;
    final item = _items.removeAt(index);
    _items.insert(0, item);
  }

  @override
  void markAsRead(String userId, String notificationId) {
    final index = _items.indexWhere(
      (item) => item.userId == userId && item.id == notificationId,
    );
    if (index >= 0) _items[index] = _items[index].copyWith(isRead: true);
  }

  @override
  void clearRead(String userId) {
    final removed = _items
        .where((item) => item.userId == userId && item.isRead)
        .map((item) => item.id)
        .toList();
    _items.removeWhere((item) => item.userId == userId && item.isRead);
    _ids.removeAll(removed);
  }
}

class NotificationService {
  NotificationService({
    SupabaseClient? client,
    NotificationStore? store,
    WaterAlertService? waterAlertService,
    ReputationService? reputationService,
    FavoriteStationsService? favoriteStationsService,
    WaterService? waterService,
    NotificationPreferencesService? preferencesService,
  }) : _client = client,
       _store = store ?? _sharedStore,
       _waterAlertService = waterAlertService ?? WaterAlertService(),
       _reputationService =
           reputationService ?? ReputationService(client: client),
       _favoriteStationsService =
           favoriteStationsService ?? FavoriteStationsService(client: client),
       _waterService = waterService ?? WaterService(),
       _preferencesService =
           preferencesService ?? NotificationPreferencesService();

  static final MemoryNotificationStore _sharedStore = MemoryNotificationStore();
  static Future<List<AppNotification>>? _inFlightNotifications;
  static final Map<String, int> _lastReputation = {};
  static final Map<String, TrustLevel> _lastTrustLevel = {};
  static final Map<String, Set<String>> _lastFavorites = {};
  static final Map<String, Set<String>> _processedEventIds = {};

  final SupabaseClient? _client;
  final NotificationStore _store;
  final WaterAlertService _waterAlertService;
  final ReputationService _reputationService;
  final FavoriteStationsService _favoriteStationsService;
  final WaterService _waterService;
  final NotificationPreferencesService _preferencesService;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<AppNotification>> getNotifications() {
    final inFlight = _inFlightNotifications;
    if (inFlight != null) return inFlight;

    late final Future<List<AppNotification>> refresh;
    refresh = _loadNotifications().whenComplete(() {
      if (identical(_inFlightNotifications, refresh)) {
        _inFlightNotifications = null;
      }
    });
    _inFlightNotifications = refresh;
    return refresh;
  }

  Future<List<AppNotification>> _loadNotifications() async {
    final userId = _requireUserId();
    await Future.wait([
      _generateWaterNotifications(userId),
      _generateReputationNotifications(userId),
      _generateFavoriteNotifications(userId),
    ]);
    _releasePostponed(userId);
    return _store.forUser(userId);
  }

  Future<void> markAsRead(String notificationId) async {
    _store.markAsRead(_requireUserId(), notificationId);
  }

  Future<int> unreadCount() async =>
      _store.forUser(_requireUserId()).where((item) => !item.isRead).length;

  Future<void> clearRead() async {
    _store.clearRead(_requireUserId());
  }

  List<AppNotification> cachedNotifications() =>
      _store.forUser(_requireUserId());

  String _requireUserId() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw const NotificationException(
        'Please sign in to view your notifications.',
      );
    }
    return userId;
  }

  Future<void> _generateWaterNotifications(String userId) async {
    try {
      final alerts = await _waterAlertService.refresh();
      for (final alert in alerts) {
        final type = switch (alert.type) {
          WaterAlertType.waterLevelRising || WaterAlertType.waterLevelFalling =>
            AppNotificationType.waterTrendChanged,
          WaterAlertType.rapidChange => AppNotificationType.waterLevelChanged,
          WaterAlertType.newCommunityReport =>
            AppNotificationType.newReportNearFavoriteStation,
          WaterAlertType.dangerousReport => AppNotificationType.dangerousReport,
        };
        _addSmart(
          userId,
          AppNotification(
            id: '$userId:water:${alert.id}',
            userId: userId,
            title: _waterTitle(alert.type),
            message: '${alert.type.label} at ${alert.stationName}.',
            type: type,
            relatedStation: alert.stationId,
            relatedReport: _reportId(alert.id),
            createdAt: alert.timestamp,
            isRead: false,
            priority: alert.type == WaterAlertType.dangerousReport
                ? NotificationPriority.critical
                : NotificationPriority.important,
          ),
        );
      }
    } on Exception {
      // Other notification sources remain available if water data is offline.
    }
  }

  Future<void> _generateReputationNotifications(String userId) async {
    try {
      final current = await _reputationService.getCurrentUserReputation();
      final previousScore = _lastReputation[userId];
      final previousLevel = _lastTrustLevel[userId];
      _lastReputation[userId] = current.reputationScore;
      _lastTrustLevel[userId] = current.trustLevel;
      if (previousScore != null && current.reputationScore > previousScore) {
        _addSmart(
          userId,
          AppNotification(
            id: '$userId:reputation:${current.reputationScore}',
            userId: userId,
            title: 'Reputation increased',
            message: 'Your reputation is now ${current.reputationScore}/100.',
            type: AppNotificationType.reputationIncreased,
            createdAt: current.updatedAt ?? DateTime.now(),
            isRead: false,
            priority: NotificationPriority.important,
          ),
        );
      }
      if (previousLevel != null &&
          current.trustLevel.index > previousLevel.index) {
        _addSmart(
          userId,
          AppNotification(
            id: '$userId:trust:${current.trustLevel.name}',
            userId: userId,
            title: 'Trust badge upgraded',
            message: 'You reached ${current.trustLevel.label} status.',
            type: AppNotificationType.trustBadgeUpgraded,
            createdAt: current.updatedAt ?? DateTime.now(),
            isRead: false,
            priority: NotificationPriority.important,
          ),
        );
      }
    } on Exception {
      // Reputation notifications are optional when the view is unavailable.
    }
  }

  Future<void> _generateFavoriteNotifications(String userId) async {
    try {
      final current = await _favoriteStationsService.getFavoriteIds();
      final previous = _lastFavorites[userId];
      _lastFavorites[userId] = Set.unmodifiable(current);
      if (previous == null) return;
      final changed = {
        ...current.difference(previous),
        ...previous.difference(current),
      };
      if (changed.isEmpty) return;
      final stations = await _waterService.getStations();
      final names = {for (final station in stations) station.id: station.name};
      for (final stationId in changed) {
        final added = current.contains(stationId);
        final stationName = names[stationId] ?? 'Water station';
        _addSmart(
          userId,
          AppNotification(
            id:
                '$userId:favorite:$stationId:$added:'
                '${FavoriteStationsService.revision.value}',
            userId: userId,
            title: 'Favourite station updated',
            message: added
                ? '$stationName was added to your favourites.'
                : '$stationName was removed from your favourites.',
            type: AppNotificationType.favoriteStationUpdate,
            relatedStation: stationId,
            createdAt: DateTime.now(),
            isRead: false,
            priority: NotificationPriority.silent,
          ),
        );
      }
    } on Exception {
      // Favourite updates do not block other notification sources.
    }
  }

  static String _waterTitle(WaterAlertType type) => switch (type) {
    WaterAlertType.waterLevelRising ||
    WaterAlertType.waterLevelFalling => 'Water trend changed',
    WaterAlertType.rapidChange => 'Water level changed rapidly',
    WaterAlertType.newCommunityReport => 'New report near a favourite',
    WaterAlertType.dangerousReport => 'Dangerous report nearby',
  };

  static String? _reportId(String alertId) {
    final match = RegExp(r'(?:report|danger):([^:]+)$').firstMatch(alertId);
    return match?.group(1);
  }

  void _addSmart(String userId, AppNotification candidate) {
    final preferences = _preferencesService.getForUser(userId);
    final category = _categoryFor(candidate.type);
    final processed = _processedEventIds.putIfAbsent(userId, () => {});
    if (!processed.add(candidate.id)) return;
    if (!preferences.isCategoryEnabled(category)) return;

    final existing = _store.forUser(userId);
    final groupable =
        candidate.type == AppNotificationType.newReportNearFavoriteStation ||
        candidate.type == AppNotificationType.dangerousReport;
    if (preferences.groupingEnabled && groupable) {
      AppNotification? match;
      for (final item in existing) {
        if (item.type == candidate.type &&
            item.relatedStation == candidate.relatedStation &&
            candidate.createdAt.difference(item.createdAt).abs() <=
                const Duration(minutes: 30)) {
          match = item;
          break;
        }
      }
      if (match != null) {
        final count = match.groupCount + 1;
        _store.upsert(
          match.copyWith(
            groupCount: count,
            createdAt: candidate.createdAt.isAfter(match.createdAt)
                ? candidate.createdAt
                : match.createdAt,
            message: _groupedMessage(candidate.type, count),
          ),
        );
        return;
      }
    }

    final withinCooldown = existing.any(
      (item) =>
          item.type == candidate.type &&
          item.relatedStation == candidate.relatedStation &&
          candidate.createdAt.difference(item.createdAt).abs() <
              preferences.cooldown,
    );
    if (withinCooldown) return;

    final now = DateTime.now();
    final quiet = preferences.isQuietAt(now);
    final delivery = switch (candidate.priority) {
      NotificationPriority.silent => NotificationDelivery.storedOnly,
      NotificationPriority.critical => NotificationDelivery.deliver,
      NotificationPriority.important =>
        quiet ? NotificationDelivery.postponed : NotificationDelivery.deliver,
    };
    _store.add(
      candidate.copyWith(
        delivery: delivery,
        deliverAfter: delivery == NotificationDelivery.postponed
            ? preferences.nextQuietEnd(now)
            : null,
      ),
    );
  }

  void _releasePostponed(String userId) {
    final now = DateTime.now();
    for (final item in _store.forUser(userId)) {
      if (item.delivery == NotificationDelivery.postponed &&
          item.deliverAfter != null &&
          !item.deliverAfter!.isAfter(now)) {
        _store.upsert(item.copyWith(delivery: NotificationDelivery.deliver));
      }
    }
  }

  static NotificationCategory _categoryFor(AppNotificationType type) =>
      switch (type) {
        AppNotificationType.waterLevelChanged ||
        AppNotificationType.waterTrendChanged =>
          NotificationCategory.waterAlerts,
        AppNotificationType.newReportNearFavoriteStation =>
          NotificationCategory.communityReports,
        AppNotificationType.dangerousReport =>
          NotificationCategory.dangerousReports,
        AppNotificationType.reputationIncreased ||
        AppNotificationType.trustBadgeUpgraded =>
          NotificationCategory.reputationTrust,
        AppNotificationType.favoriteStationUpdate =>
          NotificationCategory.favoriteStations,
      };

  static String _groupedMessage(AppNotificationType type, int count) =>
      switch (type) {
        AppNotificationType.newReportNearFavoriteStation =>
          '$count new reports near your favourite station.',
        AppNotificationType.dangerousReport =>
          '$count dangerous reports near your favourite station.',
        _ => '$count notification events.',
      };
}

class NotificationException implements Exception {
  const NotificationException(this.message);
  final String message;
}
