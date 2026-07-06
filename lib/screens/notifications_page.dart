import 'package:flutter/material.dart';

import '../services/favorite_stations_service.dart';
import '../services/water_alert_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = WaterAlertService();
  late Future<List<WaterAlert>> _alerts = _service.refresh();

  Future<void> _refresh() async {
    final alerts = _service.refresh();
    setState(() => _alerts = alerts);
    await alerts;
  }

  void _markRead(WaterAlert alert) {
    if (alert.isRead) return;
    _service.markRead(alert.id);
    setState(() => _alerts = Future.value(_service.history.alerts));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Water Alerts')),
      body: SafeArea(
        child: FutureBuilder<List<WaterAlert>>(
          future: _alerts,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final message = snapshot.error is FavoriteException
                  ? (snapshot.error! as FavoriteException).message
                  : 'Water alerts are unavailable.';
              return _AlertMessage(message: message, onRetry: _refresh);
            }
            final alerts = snapshot.data ?? const [];
            if (alerts.isEmpty) {
              return _AlertMessage(
                message: _service.isAuthenticated
                    ? 'No water alerts yet.'
                    : 'Please sign in to view alerts for favourite stations.',
                onRetry: _refresh,
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: alerts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final alert = alerts[index];
                  return Card(
                    child: ListTile(
                      onTap: () => _markRead(alert),
                      leading: Icon(
                        _icon(alert.type),
                        color: _color(alert.type),
                      ),
                      title: Text(alert.stationName),
                      subtitle: Text(
                        '${alert.type.label}\n${_timestamp(context, alert.timestamp)}',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        alert.isRead
                            ? Icons.mark_email_read_outlined
                            : Icons.circle,
                        size: alert.isRead ? 22 : 10,
                        color: alert.isRead
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

  static IconData _icon(WaterAlertType type) => switch (type) {
    WaterAlertType.waterLevelRising => Icons.trending_up_rounded,
    WaterAlertType.waterLevelFalling => Icons.trending_down_rounded,
    WaterAlertType.rapidChange => Icons.speed_rounded,
    WaterAlertType.newCommunityReport => Icons.campaign_outlined,
    WaterAlertType.dangerousReport => Icons.warning_amber_rounded,
  };

  static Color _color(WaterAlertType type) => switch (type) {
    WaterAlertType.waterLevelRising => Colors.blue,
    WaterAlertType.waterLevelFalling => Colors.orange,
    WaterAlertType.rapidChange => Colors.deepOrange,
    WaterAlertType.newCommunityReport => Colors.teal,
    WaterAlertType.dangerousReport => Colors.red,
  };

  static String _timestamp(BuildContext context, DateTime value) {
    final local = value.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date • $time';
  }
}

class _AlertMessage extends StatelessWidget {
  const _AlertMessage({required this.message, required this.onRetry});

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
