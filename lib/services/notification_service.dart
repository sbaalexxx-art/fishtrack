import 'package:supabase_flutter/supabase_flutter.dart';

import 'favorite_stations_service.dart';
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
  low,
  normal,
  high,
  critical;

  static NotificationPriority parse(Object? value) => values.firstWhere(
    (priority) => priority.name == value,
    orElse: () => normal,
  );
}

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

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    userId: userId,
    title: title,
    message: message,
    type: type,
    relatedStation: relatedStation,
    relatedReport: relatedReport,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
    priority: priority,
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
  };
}

abstract interface class NotificationStore {
  List<AppNotification> forUser(String userId);
  void add(AppNotification notification);
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
  }) : _client = client,
       _store = store ?? _sharedStore,
       _waterAlertService = waterAlertService ?? WaterAlertService(),
       _reputationService =
           reputationService ?? ReputationService(client: client),
       _favoriteStationsService =
           favoriteStationsService ?? FavoriteStationsService(client: client),
       _waterService = waterService ?? WaterService();

  static final MemoryNotificationStore _sharedStore = MemoryNotificationStore();
  static final Map<String, int> _lastReputation = {};
  static final Map<String, TrustLevel> _lastTrustLevel = {};
  static final Map<String, Set<String>> _lastFavorites = {};

  final SupabaseClient? _client;
  final NotificationStore _store;
  final WaterAlertService _waterAlertService;
  final ReputationService _reputationService;
  final FavoriteStationsService _favoriteStationsService;
  final WaterService _waterService;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<AppNotification>> getNotifications() async {
    final userId = _requireUserId();
    await Future.wait([
      _generateWaterNotifications(userId),
      _generateReputationNotifications(userId),
      _generateFavoriteNotifications(userId),
    ]);
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
        _store.add(
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
                : alert.type == WaterAlertType.rapidChange
                ? NotificationPriority.high
                : NotificationPriority.normal,
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
        _store.add(
          AppNotification(
            id: '$userId:reputation:${current.reputationScore}',
            userId: userId,
            title: 'Reputation increased',
            message: 'Your reputation is now ${current.reputationScore}/100.',
            type: AppNotificationType.reputationIncreased,
            createdAt: current.updatedAt ?? DateTime.now(),
            isRead: false,
            priority: NotificationPriority.normal,
          ),
        );
      }
      if (previousLevel != null &&
          current.trustLevel.index > previousLevel.index) {
        _store.add(
          AppNotification(
            id: '$userId:trust:${current.trustLevel.name}',
            userId: userId,
            title: 'Trust badge upgraded',
            message: 'You reached ${current.trustLevel.label} status.',
            type: AppNotificationType.trustBadgeUpgraded,
            createdAt: current.updatedAt ?? DateTime.now(),
            isRead: false,
            priority: NotificationPriority.high,
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
        _store.add(
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
            priority: NotificationPriority.low,
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
}

class NotificationException implements Exception {
  const NotificationException(this.message);
  final String message;
}
