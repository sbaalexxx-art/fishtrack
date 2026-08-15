import 'package:supabase_flutter/supabase_flutter.dart';

import 'favorite_stations_service.dart';
import 'notification_preferences_service.dart';
import 'reputation_service.dart';
import 'water_alert_service.dart';
import 'water_service.dart';
import 'diagnostics_service.dart';

enum AppNotificationType {
  waterLevelChanged('water_level_changed'),
  waterTrendChanged('water_trend_changed'),
  waterStateObserved('water_state_observed'),
  newReportNearFavoriteStation('new_report_near_favorite_station'),
  dangerousReport('dangerous_report'),
  newCatchNearSavedArea('new_catch_near_saved_area'),
  reputationIncreased('reputation_increased'),
  trustBadgeUpgraded('trust_badge_upgraded'),
  favoriteStationUpdate('favorite_station_update'),
  weatherAlert('weather_alert'),
  reportVerificationChanged('report_verification_changed'),
  catchLiked('catch_liked');

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
    this.relatedCatch,
    this.entityType,
    this.entityId,
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
        relatedCatch: json['related_catch']?.toString(),
        entityType: json['entity_type']?.toString(),
        entityId: json['entity_id']?.toString(),
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
  final String? relatedCatch;
  final String? entityType;
  final String? entityId;
  final DateTime createdAt;
  final bool isRead;
  final NotificationPriority priority;
  final NotificationDelivery delivery;
  final DateTime? deliverAfter;
  final int groupCount;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'user_id': userId,
    'title': title,
    'message': message,
    'type': type.databaseValue,
    'related_station': relatedStation,
    'related_report': relatedReport,
    'related_catch': relatedCatch,
    'entity_type': entityType,
    'entity_id': entityId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'read': isRead,
    'priority': priority.name,
    'delivery': delivery.name,
    'deliver_after': deliverAfter?.toUtc().toIso8601String(),
    'group_count': groupCount,
  };
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
    relatedCatch: relatedCatch,
    entityType: entityType,
    entityId: entityId,
    createdAt: createdAt ?? this.createdAt,
    isRead: isRead ?? this.isRead,
    priority: priority,
    delivery: delivery ?? this.delivery,
    deliverAfter: deliverAfter ?? this.deliverAfter,
    groupCount: groupCount ?? this.groupCount,
  );
}

abstract interface class NotificationStore {
  List<AppNotification> forUser(String userId);
  void add(AppNotification notification);
  void upsert(AppNotification notification);
  void replaceForUser(String userId, List<AppNotification> notifications);
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
    _trim();
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
  void replaceForUser(String userId, List<AppNotification> notifications) {
    final removed = _items
        .where((item) => item.userId == userId)
        .map((item) => item.id)
        .toList(growable: false);
    _items.removeWhere((item) => item.userId == userId);
    _ids.removeAll(removed);
    for (final notification in notifications.reversed) {
      add(notification);
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

  void _trim() {
    while (_items.length > maximumNotifications) {
      _ids.remove(_items.removeLast().id);
    }
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
           preferencesService ?? NotificationPreferencesService(client: client);

  static final MemoryNotificationStore _sharedStore = MemoryNotificationStore();
  static Future<List<AppNotification>>? _inFlightNotifications;
  static final Map<String, int> _lastReputation = {};
  static final Map<String, TrustLevel> _lastTrustLevel = {};
  static final Map<String, Set<String>> _lastFavorites = {};
  static final Map<String, Set<String>> _processedEventIds = {};
  static final Map<String, List<AppNotification>> _pendingPersistence = {};

  final SupabaseClient? _client;
  final NotificationStore _store;
  final WaterAlertService _waterAlertService;
  final ReputationService _reputationService;
  final FavoriteStationsService _favoriteStationsService;
  final WaterService _waterService;
  final NotificationPreferencesService _preferencesService;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<AppNotification>> getNotifications() {
    if (_supabase.auth.currentUser == null) {
      return Future.value(const <AppNotification>[]);
    }

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

  Stream<List<AppNotification>> watchNotifications() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return Stream<List<AppNotification>>.value(const <AppNotification>[]);
    }
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100)
        .map((rows) {
          final notifications = rows
              .map(
                (row) =>
                    AppNotification.fromJson(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false);
          _store.replaceForUser(userId, notifications);
          return notifications;
        });
  }

  Future<List<AppNotification>> _loadNotifications() async {
    final stopwatch = Stopwatch()..start();
    final userId = _requireUserId();
    await _preferencesService.loadForUser(userId);
    await Future.wait([
      _generateWaterNotifications(userId),
      _generateReputationNotifications(userId),
      _generateFavoriteNotifications(userId),
    ]);
    _releasePostponed(userId);
    await _persistPending(userId);
    try {
      final rows = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);
      final notifications = rows
          .map(
            (row) => AppNotification.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false);
      _store.replaceForUser(userId, notifications);
      stopwatch.stop();
      DiagnosticsService.instance.record(
        category: DiagnosticCategory.notifications,
        operation: 'inbox_load',
        message: 'available',
        duration: stopwatch.elapsed,
        metadata: <String, Object?>{
          'items': notifications.length,
          'unread': notifications.where((item) => !item.isRead).length,
        },
      );
      return notifications;
    } on Exception catch (error, stackTrace) {
      if (stopwatch.isRunning) stopwatch.stop();
      DiagnosticsService.instance.recordError(
        category: DiagnosticCategory.notifications,
        operation: 'inbox_load',
        error: error,
        stackTrace: stackTrace,
      );
      final cached = _store.forUser(userId);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> markAsRead(String notificationId) async {
    final userId = _requireUserId();
    await _supabase
        .from('notifications')
        .update({'read': true})
        .eq('id', notificationId)
        .eq('user_id', userId);
    _store.markAsRead(userId, notificationId);
  }

  Future<int> unreadCount() async {
    final notifications = await getNotifications();
    return notifications.where((item) => !item.isRead).length;
  }

  Future<void> clearRead() async {
    final userId = _requireUserId();
    await _supabase
        .from('notifications')
        .delete()
        .eq('user_id', userId)
        .eq('read', true);
    _store.clearRead(userId);
  }

  List<AppNotification> cachedNotifications() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const <AppNotification>[];
    return _store.forUser(userId);
  }

  String _requireUserId() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw const NotificationException(
        'Please sign in to view your notifications.',
      );
    }
    return userId;
  }

  Future<void> _persistPending(String userId) async {
    final pending = List<AppNotification>.from(
      _pendingPersistence.remove(userId) ?? const [],
    );
    if (pending.isEmpty) return;
    for (final item in pending) {
      try {
        await _supabase.rpc(
          'enqueue_own_notification_v1',
          params: {
            'p_type': item.type.databaseValue,
            'p_category': _categoryFor(item.type).name,
            'p_title': item.title,
            'p_message': item.message,
            'p_priority': item.priority.name,
            'p_related_station': item.relatedStation,
            'p_related_report': item.relatedReport,
            'p_entity_type': item.entityType,
            'p_entity_id': item.entityId,
            'p_data': <String, dynamic>{'group_count': item.groupCount},
            'p_dedupe_key': item.id,
          },
        );
      } on Exception {
        _pendingPersistence.putIfAbsent(userId, () => []).add(item);
      }
    }
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
            entityType:
                alert.type == WaterAlertType.newCommunityReport ||
                    alert.type == WaterAlertType.dangerousReport
                ? 'report'
                : 'station',
            entityId: _reportId(alert.id) ?? alert.stationId,
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
            entityType: 'profile',
            entityId: userId,
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
            entityType: 'profile',
            entityId: userId,
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
            entityType: 'station',
            entityId: stationId,
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
        final grouped = match.copyWith(
          groupCount: count,
          createdAt: candidate.createdAt.isAfter(match.createdAt)
              ? candidate.createdAt
              : match.createdAt,
          message: _groupedMessage(candidate.type, count),
        );
        _store.upsert(grouped);
        _pendingPersistence.putIfAbsent(userId, () => []).add(grouped);
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
    final resolved = candidate.copyWith(
      delivery: delivery,
      deliverAfter: delivery == NotificationDelivery.postponed
          ? preferences.nextQuietEnd(now)
          : null,
    );
    _store.add(resolved);
    _pendingPersistence.putIfAbsent(userId, () => []).add(resolved);
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
        AppNotificationType.waterTrendChanged ||
        AppNotificationType.waterStateObserved =>
          NotificationCategory.waterAlerts,
        AppNotificationType.weatherAlert => NotificationCategory.weatherAlerts,
        AppNotificationType.newReportNearFavoriteStation ||
        AppNotificationType.reportVerificationChanged =>
          NotificationCategory.communityReports,
        AppNotificationType.dangerousReport =>
          NotificationCategory.dangerousReports,
        AppNotificationType.newCatchNearSavedArea ||
        AppNotificationType.catchLiked => NotificationCategory.catchActivity,
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
