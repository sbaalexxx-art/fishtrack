import 'package:flutter/material.dart';

import '../services/notification_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = NotificationService();
  late Future<List<AppNotification>> _notifications = _service
      .getNotifications();

  Future<void> _refresh() async {
    final notifications = _service.getNotifications();
    setState(() => _notifications = notifications);
    await notifications;
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    await _service.markAsRead(notification.id);
    if (mounted) {
      setState(
        () => _notifications = Future.value(_service.cachedNotifications()),
      );
    }
  }

  Future<void> _clearRead() async {
    await _service.clearRead();
    if (mounted) {
      setState(
        () => _notifications = Future.value(_service.cachedNotifications()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<List<AppNotification>>(
          future: _notifications,
          builder: (context, snapshot) {
            final unread =
                snapshot.data
                    ?.where((notification) => !notification.isRead)
                    .length ??
                0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Notifications'),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Badge(label: Text('$unread')),
                ],
              ],
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Clear read notifications',
            onPressed: _clearRead,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<AppNotification>>(
          future: _notifications,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message = snapshot.error is NotificationException
                  ? (snapshot.error! as NotificationException).message
                  : 'Notifications are unavailable.';
              return _NotificationMessage(message: message, onRetry: _refresh);
            }
            final notifications = snapshot.data ?? const [];
            if (notifications.isEmpty) {
              return _NotificationMessage(
                message: 'No notifications yet.',
                onRetry: _refresh,
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final notification = notifications[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _markRead(notification),
                      leading: Icon(
                        _icon(notification.type),
                        color: _color(notification.priority),
                      ),
                      title: Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.isRead
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '${notification.message}\n'
                        '${_relativeTime(notification.createdAt)}',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        notification.isRead
                            ? Icons.mark_email_read_outlined
                            : Icons.circle,
                        size: notification.isRead ? 22 : 10,
                        color: notification.isRead
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  static IconData _icon(AppNotificationType type) => switch (type) {
    AppNotificationType.waterLevelChanged => Icons.water_rounded,
    AppNotificationType.waterTrendChanged => Icons.trending_up_rounded,
    AppNotificationType.newReportNearFavoriteStation => Icons.campaign_outlined,
    AppNotificationType.dangerousReport => Icons.warning_amber_rounded,
    AppNotificationType.reputationIncreased => Icons.add_chart_rounded,
    AppNotificationType.trustBadgeUpgraded => Icons.verified_rounded,
    AppNotificationType.favoriteStationUpdate => Icons.favorite_rounded,
  };

  static Color _color(NotificationPriority priority) => switch (priority) {
    NotificationPriority.low => Colors.grey,
    NotificationPriority.normal => Colors.blue,
    NotificationPriority.high => Colors.orange,
    NotificationPriority.critical => Colors.red,
  };

  static String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${value.toLocal().day}.${value.toLocal().month}.'
        '${value.toLocal().year}';
  }
}

class _NotificationMessage extends StatelessWidget {
  const _NotificationMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 52),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Refresh')),
        ],
      ),
    ),
  );
}
