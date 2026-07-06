import 'package:fishtrack/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppNotification notification({
    required String id,
    required String userId,
    bool isRead = false,
  }) => AppNotification(
    id: id,
    userId: userId,
    title: 'Water trend changed',
    message: 'Water level rising at Test Station.',
    type: AppNotificationType.waterTrendChanged,
    relatedStation: 'station-1',
    createdAt: DateTime.utc(2026, 7, 6),
    isRead: isRead,
    priority: NotificationPriority.important,
  );

  test('notification JSON uses backend-ready field names', () {
    final original = notification(id: 'event-1', userId: 'user-1');
    final json = original.toJson();
    final restored = AppNotification.fromJson(json);

    expect(json['user_id'], 'user-1');
    expect(json['related_station'], 'station-1');
    expect(json['read'], isFalse);
    expect(restored.type, AppNotificationType.waterTrendChanged);
    expect(restored.priority, NotificationPriority.important);
  });

  test('store scopes notifications and read state per user', () {
    final store = MemoryNotificationStore();
    store.add(notification(id: 'event-1', userId: 'user-1'));
    store.add(notification(id: 'event-2', userId: 'user-2'));

    store.markAsRead('user-1', 'event-1');

    expect(store.forUser('user-1').single.isRead, isTrue);
    expect(store.forUser('user-2').single.isRead, isFalse);
  });

  test('clearRead keeps unread notifications', () {
    final store = MemoryNotificationStore();
    store.add(notification(id: 'read', userId: 'user-1', isRead: true));
    store.add(notification(id: 'unread', userId: 'user-1'));

    store.clearRead('user-1');

    expect(store.forUser('user-1').single.id, 'unread');
  });
}
