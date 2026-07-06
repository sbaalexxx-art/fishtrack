import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

import '../models/station.dart';
import '../services/water_service.dart';
import '../widgets/loading_list_skeleton.dart';
import '../widgets/station_card.dart';
import 'station_details_page.dart';

class WaterLevelPage extends StatefulWidget {
  const WaterLevelPage({super.key});

  @override
  State<WaterLevelPage> createState() => _WaterLevelPageState();
}

class _WaterLevelPageState extends State<WaterLevelPage> {
  final WaterService _waterService = WaterService();
  late Future<List<Station>> _stations = _load();

  Future<List<Station>> _load({bool forceRefresh = false}) =>
      _waterService.getStations(forceRefresh: forceRefresh);

  Future<void> _refresh() async {
    final stations = _load(forceRefresh: true);
    setState(() => _stations = stations);
    await stations;
  }

  Future<void> _openStation(Station station) async {
    _waterService.selectStation(station);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StationDetailsPage(station: station),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.waterLevels), centerTitle: true),
      body: SafeArea(
        child: FutureBuilder<List<Station>>(
          future: _stations,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingListSkeleton();
            }
            if (snapshot.hasError) {
              return _WaterMessage(
                icon: Icons.cloud_off_outlined,
                message: context.l10n.waterProviderUnavailable,
                onRefresh: _refresh,
              );
            }
            final stations = snapshot.data ?? const [];
            if (stations.isEmpty) {
              return _WaterMessage(
                icon: Icons.water_drop_outlined,
                message: context.l10n.noWaterData,
                onRefresh: _refresh,
              );
            }
            final latestUpdate = stations
                .map((station) => station.lastUpdate)
                .where((timestamp) => timestamp.millisecondsSinceEpoch > 0)
                .fold<DateTime?>(
                  null,
                  (latest, timestamp) =>
                      latest == null || timestamp.isAfter(latest)
                      ? timestamp
                      : latest,
                );
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.water_drop,
                            color: Colors.blue,
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Live Water Levels',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(context.l10n.monitoredStations(stations.length)),
                          const SizedBox(height: 12),
                          Text(
                            latestUpdate == null
                                ? 'Update time unavailable'
                                : _relativeUpdate(latestUpdate),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Monitored stations',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final station in stations)
                    StationCard(
                      station: station,
                      onTap: () => _openStation(station),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static String _relativeUpdate(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp.toLocal());
    if (difference.isNegative || difference.inMinutes < 1) {
      return 'Updated just now';
    }
    if (difference.inMinutes < 60) {
      return 'Updated ${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) return 'Updated ${difference.inHours} h ago';
    return 'Updated ${difference.inDays} d ago';
  }
}

class _WaterMessage extends StatelessWidget {
  const _WaterMessage({
    required this.icon,
    required this.message,
    required this.onRefresh,
  });

  final IconData icon;
  final String message;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(message, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
