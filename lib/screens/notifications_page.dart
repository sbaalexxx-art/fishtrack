import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../services/notification_service.dart';
import '../widgets/loading_list_skeleton.dart';
import 'notification_preferences_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = NotificationService();
  late List<AppNotification> _notifications;
  Object? _loadError;
  bool _isLoading = false;
  Future<void>? _refreshInFlight;

  @override
  void initState() {
    super.initState();
    try {
      _notifications = _service.cachedNotifications();
    } on NotificationException catch (error) {
      _notifications = const [];
      _loadError = error;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final hadCachedNotifications = _notifications.isNotEmpty;
    if (!hadCachedNotifications) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    final refresh = _service.getNotifications();
    late final Future<void> operation;
    operation = refresh
        .then(
          (notifications) {
            if (mounted) {
              setState(() {
                _notifications = notifications;
                _loadError = null;
              });
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted && !hadCachedNotifications) {
              setState(() => _loadError = error);
            }
          },
        )
        .whenComplete(() {
          if (mounted) {
            setState(() => _isLoading = false);
          }
          if (identical(_refreshInFlight, operation)) {
            _refreshInFlight = null;
          }
        });
    _refreshInFlight = operation;
    return operation;
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    try {
      await _service.markAsRead(notification.id);
      if (mounted) {
        setState(() => _notifications = _service.cachedNotifications());
      }
    } on NotificationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _clearRead() async {
    try {
      await _service.clearRead();
      if (mounted) {
        setState(() => _notifications = _service.cachedNotifications());
      }
    } on NotificationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.notifications,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const Key('notifications-alert-rules-action'),
            tooltip: Localizations.localeOf(context).languageCode == 'ro'
                ? 'Alerte personale'
                : 'Personal alerts',
            onPressed: () => AppNavigator.open(context, AppDestination.alerts),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          PopupMenuButton<_NotificationMenuAction>(
            key: const Key('notifications-more-action'),
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            onSelected: (action) {
              switch (action) {
                case _NotificationMenuAction.preferences:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationPreferencesPage(),
                    ),
                  );
                case _NotificationMenuAction.clearRead:
                  _clearRead();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _NotificationMenuAction.preferences,
                child: ListTile(
                  leading: const Icon(Icons.tune_rounded),
                  title: Text(context.l10n.notificationPreferencesTooltip),
                ),
              ),
              PopupMenuItem(
                value: _NotificationMenuAction.clearRead,
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(context.l10n.clearReadNotifications),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading && _notifications.isEmpty
            ? const LoadingListSkeleton()
            : _loadError != null && _notifications.isEmpty
            ? _NotificationMessage(
                message: _loadError is NotificationException
                    ? (_loadError! as NotificationException).message
                    : context.l10n.notificationsUnavailable,
                onRetry: _refresh,
              )
            : _notifications.isEmpty
            ? _NotificationMessage(
                message: context.l10n.noNotifications,
                onRetry: _refresh,
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    return Card(
                      child: ListTile(
                        onTap: () => _markRead(notification),
                        leading: Icon(
                          _icon(notification.type),
                          color: _color(notification.priority),
                        ),
                        title: Text(
                          notification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: notification.isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${notification.message}\n'
                          '${_relativeTime(context, notification.createdAt)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
              ),
      ),
    );
  }

  static IconData _icon(AppNotificationType type) => switch (type) {
    AppNotificationType.waterLevelChanged => Icons.water_rounded,
    AppNotificationType.waterTrendChanged => Icons.trending_up_rounded,
    AppNotificationType.waterStateObserved => Icons.water_drop_outlined,
    AppNotificationType.newReportNearFavoriteStation => Icons.campaign_outlined,
    AppNotificationType.dangerousReport => Icons.warning_amber_rounded,
    AppNotificationType.newCatchNearSavedArea => Icons.set_meal_rounded,
    AppNotificationType.reputationIncreased => Icons.add_chart_rounded,
    AppNotificationType.trustBadgeUpgraded => Icons.verified_rounded,
    AppNotificationType.favoriteStationUpdate => Icons.favorite_rounded,
    AppNotificationType.weatherAlert => Icons.cloud_outlined,
    AppNotificationType.reportVerificationChanged => Icons.fact_check_outlined,
    AppNotificationType.catchLiked => Icons.favorite_border_rounded,
  };

  static Color _color(NotificationPriority priority) => switch (priority) {
    NotificationPriority.silent => Colors.grey,
    NotificationPriority.important => Colors.blue,
    NotificationPriority.critical => Colors.red,
  };

  static String _relativeTime(BuildContext context, DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return context.l10n.justNow;
    }
    if (difference.inHours < 1) {
      return context.l10n.minutesAgo(difference.inMinutes);
    }
    if (difference.inDays < 1) {
      return context.l10n.hoursAgo(difference.inHours);
    }
    if (difference.inDays < 7) {
      return context.l10n.daysAgo(difference.inDays);
    }
    return '${value.toLocal().day}.${value.toLocal().month}.'
        '${value.toLocal().year}';
  }
}

enum _NotificationMenuAction { preferences, clearRead }

class _NotificationMessage extends StatelessWidget {
  const _NotificationMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRetry,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded, size: 52),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: Text(context.l10n.refresh),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
