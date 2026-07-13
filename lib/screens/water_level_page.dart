import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters/water_freshness_formatter.dart';
import '../l10n/l10n.dart';

import '../models/station.dart';
import '../services/water_service.dart';
import '../widgets/station_card.dart';
import 'station_details_page.dart';

class WaterLevelPage extends StatefulWidget {
  const WaterLevelPage({super.key});

  @override
  State<WaterLevelPage> createState() => _WaterLevelPageState();
}

class _WaterLevelPageState extends State<WaterLevelPage> {
  final WaterService _waterService = WaterService();
  StreamSubscription<WaterStationBatchResult>? _batchSubscription;
  Completer<void>? _loadCompletion;
  WaterStationBatchResult? _visibleBatch;
  WaterStationBatchResult? _refreshBaseBatch;
  bool _fallbackMessageShown = false;
  bool _unexpectedLoadFailed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startProgressiveLoad());
  }

  @override
  void dispose() {
    _loadGeneration++;
    _completeActiveLoad();
    unawaited(_batchSubscription?.cancel());
    super.dispose();
  }

  Future<void> _startProgressiveLoad({bool forceRefresh = false}) {
    final generation = ++_loadGeneration;
    _completeActiveLoad();
    unawaited(_batchSubscription?.cancel());
    final completion = Completer<void>();
    _loadCompletion = completion;
    _refreshBaseBatch = forceRefresh && _isUsable(_visibleBatch)
        ? _visibleBatch
        : null;

    _batchSubscription = _waterService
        .getProgressiveStationBatch(forceRefresh: forceRefresh)
        .listen(
          (incomingBatch) {
            if (!mounted || generation != _loadGeneration) return;
            if (incomingBatch.stationListLoadFailed &&
                _isUsable(_visibleBatch)) {
              _showProviderUnavailable();
              return;
            }

            final displayedBatch = _refreshBaseBatch == null
                ? incomingBatch
                : _mergeWithPrevious(_refreshBaseBatch!, incomingBatch);
            setState(() {
              _visibleBatch = displayedBatch;
              _unexpectedLoadFailed = false;
            });
            _showFallbackMessageIfNeeded(incomingBatch);
          },
          onError: (Object _) {
            if (!mounted || generation != _loadGeneration) return;
            if (_isUsable(_visibleBatch)) {
              _showProviderUnavailable();
            } else {
              setState(() => _unexpectedLoadFailed = true);
            }
          },
          onDone: () {
            if (generation != _loadGeneration) return;
            _refreshBaseBatch = null;
            _completeActiveLoad();
          },
          cancelOnError: false,
        );
    return completion.future;
  }

  void _completeActiveLoad() {
    final completion = _loadCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    _loadCompletion = null;
  }

  void _showProviderUnavailable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.waterProviderUnavailable)),
      );
    });
  }

  void _showFallbackMessageIfNeeded(WaterStationBatchResult batch) {
    if (!batch.isStationListStaleFallback || _fallbackMessageShown) return;
    _fallbackMessageShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.cachedDataFallback)));
    });
  }

  static bool _isUsable(WaterStationBatchResult? batch) =>
      batch != null && !batch.stationListLoadFailed;

  Future<void> _refresh() {
    final activeLoad = _loadCompletion;
    final batch = _visibleBatch;
    if (activeLoad != null &&
        !activeLoad.isCompleted &&
        (batch == null || !batch.isComplete || _refreshBaseBatch != null)) {
      return activeLoad.future;
    }
    return _startProgressiveLoad(forceRefresh: true);
  }

  static WaterStationBatchResult _mergeWithPrevious(
    WaterStationBatchResult previous,
    WaterStationBatchResult incoming,
  ) {
    final mergedResults = <String, WaterUiResult>{};
    var stationWithReadingCount = 0;
    var stationWithoutDataCount = 0;
    var providerErrorCount = 0;
    DateTime? latestMeasurementTimestamp;
    for (final station in incoming.stations) {
      final result =
          incoming.resultsByStationId[station.id] ??
          previous.resultsByStationId[station.id];
      if (result == null) continue;
      mergedResults[station.id] = result;
      final reading = result.latestReading;
      if (reading != null &&
          reading.value.isFinite &&
          reading.timestamp.millisecondsSinceEpoch > 0) {
        stationWithReadingCount++;
        final timestamp = result.measurementTimestamp;
        if (timestamp != null &&
            timestamp.millisecondsSinceEpoch > 0 &&
            (latestMeasurementTimestamp == null ||
                timestamp.isAfter(latestMeasurementTimestamp))) {
          latestMeasurementTimestamp = timestamp;
        }
      } else {
        stationWithoutDataCount++;
      }
      if (result.status == WaterUiStatus.providerError) providerErrorCount++;
    }

    return WaterStationBatchResult(
      stations: incoming.stations,
      resultsByStationId: Map<String, WaterUiResult>.unmodifiable(
        mergedResults,
      ),
      totalStationCount: incoming.totalStationCount,
      stationWithReadingCount: stationWithReadingCount,
      stationWithoutDataCount: stationWithoutDataCount,
      providerErrorCount: providerErrorCount,
      latestMeasurementTimestamp: latestMeasurementTimestamp,
      isStationListStaleFallback: incoming.isStationListStaleFallback,
      stationListLoadFailed: false,
      safeDiagnosticMessage: incoming.safeDiagnosticMessage,
      isComplete: incoming.isComplete,
    );
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
    final batch = _visibleBatch;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.waterLevels), centerTitle: true),
      body: SafeArea(
        child: _unexpectedLoadFailed || batch?.stationListLoadFailed == true
            ? _WaterMessage(
                icon: Icons.cloud_off_outlined,
                message: context.l10n.waterProviderUnavailable,
                onRefresh: _refresh,
              )
            : batch?.isComplete == true && batch!.stations.isEmpty
            ? _WaterMessage(
                icon: Icons.water_drop_outlined,
                message: context.l10n.noWaterData,
                onRefresh: _refresh,
              )
            : RefreshIndicator(
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
                              _officialWaterLevelsTitle(context),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              batch == null
                                  ? _loadingStationsLabel(context)
                                  : _stationSummaryLabel(
                                      context,
                                      total: batch.totalStationCount,
                                      withReading:
                                          batch.stationWithReadingCount,
                                    ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              batch == null ||
                                      (!batch.isComplete &&
                                          batch.latestMeasurementTimestamp ==
                                              null)
                                  ? _latestMeasurementLoadingLabel(context)
                                  : _latestMeasurementLabel(
                                      context,
                                      batch.latestMeasurementTimestamp,
                                      isStale: _latestMeasurementIsStale(batch),
                                    ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (batch != null &&
                                batch.providerErrorCount > 0) ...[
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (batch == null)
                      for (var index = 0; index < 4; index++)
                        const _StationCardSkeleton()
                    else
                      for (final station in batch.stations)
                        KeyedSubtree(
                          key: ValueKey<String>('water-${station.id}'),
                          child: batch.resultsByStationId[station.id] == null
                              ? const _StationCardSkeleton()
                              : StationCard(
                                  station: station,
                                  waterResult:
                                      batch.resultsByStationId[station.id],
                                  onTap: () => _openStation(station),
                                ),
                        ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  static bool _isRomanian(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ro';

  static String _officialWaterLevelsTitle(BuildContext context) =>
      _isRomanian(context)
      ? 'Niveluri oficiale ale apei'
      : 'Official water levels';

  static String _loadingStationsLabel(BuildContext context) =>
      _isRomanian(context)
      ? 'Se \u00eencarc\u0103 sta\u021biile\u2026'
      : 'Loading stations\u2026';

  static String _latestMeasurementLoadingLabel(BuildContext context) =>
      _isRomanian(context)
      ? 'Cea mai recent\u0103: se \u00eencarc\u0103\u2026'
      : 'Latest: loading\u2026';

  static String _stationSummaryLabel(
    BuildContext context, {
    required int total,
    required int withReading,
  }) => _isRomanian(context)
      ? '$total sta\u021bii \u2022 $withReading cu date'
      : '$total stations \u2022 $withReading with data';

  static String _latestMeasurementLabel(
    BuildContext context,
    DateTime? timestamp, {
    required bool isStale,
  }) {
    final isRo = _isRomanian(context);
    final prefix = isRo ? 'Cea mai recent\u0103' : 'Latest';
    if (timestamp == null || timestamp.millisecondsSinceEpoch <= 0) {
      return '$prefix: ${isRo ? 'indisponibil\u0103' : 'unavailable'}';
    }

    final freshness = WaterFreshnessFormatter.format(
      measurementTimestamp: timestamp,
      now: DateTime.now(),
      isStale: isStale,
      locale: Localizations.localeOf(context).languageCode,
    );
    return '$prefix: $freshness';
  }

  static bool _latestMeasurementIsStale(WaterStationBatchResult batch) {
    final latestTimestamp = batch.latestMeasurementTimestamp;
    if (latestTimestamp == null) return false;
    for (final result in batch.resultsByStationId.values) {
      if (result.measurementTimestamp?.millisecondsSinceEpoch ==
          latestTimestamp.millisecondsSinceEpoch) {
        return result.isStale;
      }
    }
    return false;
  }

  static String _partialResultLabel(BuildContext context, int errorCount) =>
      _isRomanian(context)
      ? '$errorCount ${errorCount == 1 ? 'sta\u021bie nu s-a putut actualiza' : 'sta\u021bii nu s-au putut actualiza'}'
      : '$errorCount ${errorCount == 1 ? 'station could not be updated' : 'stations could not be updated'}';
}

class _StationCardSkeleton extends StatelessWidget {
  const _StationCardSkeleton();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: const SizedBox(
        height: 88,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _SkeletonBlock(width: 40, height: 40, isCircular: true),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: .62,
                      child: _SkeletonBlock(height: 14),
                    ),
                    SizedBox(height: 10),
                    FractionallySizedBox(
                      widthFactor: .88,
                      child: _SkeletonBlock(height: 11),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              _SkeletonBlock(width: 54, height: 18),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    this.width,
    this.isCircular = false,
  });

  final double? width;
  final double height;
  final bool isCircular;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(isCircular ? height / 2 : 7),
    ),
  );
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
