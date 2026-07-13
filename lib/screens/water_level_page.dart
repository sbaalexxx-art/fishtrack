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
  WaterStationBatchResult? _visibleBatch;
  late Future<WaterStationBatchResult> _batch = _load();
  bool _fallbackMessageShown = false;

  Future<WaterStationBatchResult> _load({bool forceRefresh = false}) async {
    final result = await _waterService.getStationBatchResult(
      forceRefresh: forceRefresh,
    );
    if (!forceRefresh) _visibleBatch = result;
    return result;
  }

  Future<void> _refresh() async {
    final previousBatch = _visibleBatch;
    try {
      final refreshedBatch = await _load(forceRefresh: true);
      if (!mounted) return;

      if (refreshedBatch.stationListLoadFailed &&
          previousBatch != null &&
          !previousBatch.stationListLoadFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.waterProviderUnavailable)),
        );
        return;
      }

      setState(() {
        _visibleBatch = refreshedBatch;
        _batch = Future<WaterStationBatchResult>.value(refreshedBatch);
        if (!refreshedBatch.isStationListStaleFallback) {
          _fallbackMessageShown = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.waterProviderUnavailable)),
      );
    }
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
        child: FutureBuilder<WaterStationBatchResult>(
          future: _batch,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                _visibleBatch == null) {
              return const LoadingListSkeleton();
            }
            if (snapshot.hasError && _visibleBatch == null) {
              return _WaterMessage(
                icon: Icons.cloud_off_outlined,
                message: context.l10n.waterProviderUnavailable,
                onRefresh: _refresh,
              );
            }
            final batch = snapshot.data ?? _visibleBatch;
            if (batch == null || batch.stationListLoadFailed) {
              return _WaterMessage(
                icon: Icons.cloud_off_outlined,
                message: context.l10n.waterProviderUnavailable,
                onRefresh: _refresh,
              );
            }
            _visibleBatch = batch;
            if (batch.isStationListStaleFallback && !_fallbackMessageShown) {
              _fallbackMessageShown = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.cachedDataFallback)),
                  );
                }
              });
            }
            final stations = batch.stations;
            if (stations.isEmpty) {
              return _WaterMessage(
                icon: Icons.water_drop_outlined,
                message: context.l10n.noWaterData,
                onRefresh: _refresh,
              );
            }
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
                          Text(
                            context.l10n.liveWaterLevels,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _stationSummaryLabel(
                              context,
                              total: batch.totalStationCount,
                              withReading: batch.stationWithReadingCount,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _latestMeasurementLabel(
                              context,
                              batch.latestMeasurementTimestamp,
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (batch.providerErrorCount > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              _partialResultLabel(
                                context,
                                batch.providerErrorCount,
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.l10n.monitoredStationsTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final station in stations)
                    StationCard(
                      station: station,
                      waterResult: batch.resultsByStationId[station.id],
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

  static bool _isRomanian(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ro';

  static String _stationSummaryLabel(
    BuildContext context, {
    required int total,
    required int withReading,
  }) => _isRomanian(context)
      ? '$total sta\u021bii \u2022 $withReading cu date'
      : '$total stations \u2022 $withReading with data';

  static String _latestMeasurementLabel(
    BuildContext context,
    DateTime? timestamp,
  ) {
    final isRo = _isRomanian(context);
    final prefix = isRo ? 'Cea mai recent\u0103' : 'Latest';
    if (timestamp == null || timestamp.millisecondsSinceEpoch <= 0) {
      return '$prefix: ${isRo ? 'indisponibil\u0103' : 'unavailable'}';
    }

    final measuredAge = DateTime.now().difference(timestamp.toLocal());
    final age = measuredAge.isNegative ? Duration.zero : measuredAge;
    return '$prefix: ${_relativeAgeLabel(age, isRo: isRo)}';
  }

  static String _relativeAgeLabel(Duration age, {required bool isRo}) {
    if (age.inMinutes < 1) return isRo ? 'acum' : 'now';
    if (age.inMinutes < 60) {
      final value = age.inMinutes;
      if (isRo) return 'acum $value ${value == 1 ? 'minut' : 'minute'}';
      return '$value ${value == 1 ? 'minute' : 'minutes'} ago';
    }
    if (age.inHours < 24) {
      final value = age.inHours;
      if (isRo) return 'acum $value ${value == 1 ? 'or\u0103' : 'ore'}';
      return '$value ${value == 1 ? 'hour' : 'hours'} ago';
    }
    final value = age.inDays;
    if (isRo) return 'acum $value ${value == 1 ? 'zi' : 'zile'}';
    return '$value ${value == 1 ? 'day' : 'days'} ago';
  }

  static String _partialResultLabel(BuildContext context, int errorCount) =>
      _isRomanian(context)
      ? '$errorCount ${errorCount == 1 ? 'sta\u021bie nu s-a putut actualiza' : 'sta\u021bii nu s-au putut actualiza'}'
      : '$errorCount ${errorCount == 1 ? 'station could not be updated' : 'stations could not be updated'}';
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
