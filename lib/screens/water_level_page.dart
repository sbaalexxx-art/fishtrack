import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters/water_freshness_formatter.dart';
import '../core/context/selected_context.dart';
import '../core/navigation/app_destination.dart';
import '../core/navigation/app_navigator.dart';
import '../core/water/water_history_analysis.dart';
import '../l10n/l10n.dart';
import '../models/station.dart';
import '../models/water_level.dart';
import '../models/weather.dart';
import '../services/water_service.dart';
import '../services/weather_service.dart';

enum WaterDetailsPeriod {
  oneDay(Duration(days: 1)),
  threeDays(Duration(days: 3)),
  sevenDays(Duration(days: 7)),
  @Deprecated('Kept only for source compatibility; use 7 or 30 days.')
  fourteenDays(Duration(days: 14)),
  thirtyDays(Duration(days: 30));

  const WaterDetailsPeriod(this.duration);

  final Duration duration;
}

String waterDetailsRefreshLabel(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ro'
    ? 'Actualizare…'
    : 'Updating…';

String waterDetailsPeriodLabel(
  BuildContext context,
  WaterDetailsPeriod period,
) {
  final days = period.duration.inDays;
  final isRo = Localizations.localeOf(context).languageCode == 'ro';
  if (days == 1) return isRo ? '1 zi' : '1 day';
  return isRo ? '$days zile' : '$days days';
}

WaterHomeStationSelection waterDetailsSelectionForHandoff(
  WaterHomeStationSelection resolvedSelection,
  Station? handedOffStation,
) => handedOffStation == null
    ? resolvedSelection
    : WaterHomeStationSelection(
        mode: resolvedSelection.mode,
        station: handedOffStation,
        candidates: resolvedSelection.candidates,
        canonicalStations: resolvedSelection.canonicalStations,
      );

WaterTrendResult? waterHubCanonicalTrend(WaterUiResult? result) =>
    result?.effectiveCanonicalTrend;

@immutable
class WaterHistoryChartSegment {
  const WaterHistoryChartSegment(this.realObservations);

  final List<WaterLevel> realObservations;

  bool get hasLine => realObservations.length >= 2;
  bool get usesBezier => realObservations.length >= 3;
}

List<WaterHistoryChartSegment> waterHistoryChartSegments(
  List<WaterLevel> readings,
) => List<WaterHistoryChartSegment>.unmodifiable(
  realWaterHistorySegments(readings).map(
    (segment) =>
        WaterHistoryChartSegment(List<WaterLevel>.unmodifiable(segment)),
  ),
);

WaterLevel? waterHistoryObservationForTimestamp(
  List<WaterHistoryChartSegment> segments,
  double timestamp,
) {
  final timestampMillis = timestamp.round();
  for (final segment in segments) {
    for (final observation in segment.realObservations) {
      if (observation.timestamp.toUtc().millisecondsSinceEpoch ==
          timestampMillis) {
        return observation;
      }
    }
  }
  return null;
}

class WaterDetailsSummary {
  const WaterDetailsSummary._({
    required this.readings,
    required this.minimum,
    required this.maximum,
    required this.change,
    required this.coverage,
  });

  final List<WaterLevel> readings;
  final double? minimum;
  final double? maximum;
  final double? change;
  final Duration? coverage;

  bool get hasChart => readings.length >= 2;
  WaterTrend? get trend => waterTrendFromRealDelta(change);

  static WaterDetailsSummary fromHistory(
    List<WaterLevel> history,
    WaterDetailsPeriod period, {
    String? stationId,
  }) {
    final readings = realWaterHistorySeries(
      history,
      period: period.duration,
      stationId: stationId,
    );
    if (readings.isEmpty) {
      return const WaterDetailsSummary._(
        readings: <WaterLevel>[],
        minimum: null,
        maximum: null,
        change: null,
        coverage: null,
      );
    }

    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = readings
        .map((reading) => reading.value)
        .reduce((a, b) => a > b ? a : b);
    return WaterDetailsSummary._(
      readings: List<WaterLevel>.unmodifiable(readings),
      minimum: minimum,
      maximum: maximum,
      change: readings.length < 2
          ? null
          : readings.last.value - readings.first.value,
      coverage: readings.length < 2
          ? null
          : readings.last.timestamp.difference(readings.first.timestamp),
    );
  }
}

class WaterLevelPage extends StatefulWidget {
  const WaterLevelPage({
    super.key,
    this.initialStation,
    this.initialPeriod,
    this.waterService,
  });

  final Station? initialStation;
  final WaterDetailsPeriod? initialPeriod;
  final WaterService? waterService;

  @override
  State<WaterLevelPage> createState() => _WaterLevelPageState();
}

class _WaterLevelPageState extends State<WaterLevelPage> {
  late final WaterService _waterService;
  StreamSubscription<WaterUiResult>? _resultSubscription;

  WaterHomeStationSelection? _selection;
  Station? _station;
  WaterUiResult? _result;
  late WaterDetailsPeriod _period;
  bool _loadingStation = true;
  bool _loadingResult = false;
  bool _loadFailed = false;
  bool _useInitialStation = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _waterService = widget.waterService ?? WaterService();
    _period = widget.initialPeriod ?? WaterDetailsPeriod.sevenDays;
    final initialStation =
        widget.initialStation ?? _waterService.lastAutomaticStation;
    if (initialStation != null) {
      _station = initialStation;
      _result = _waterService.cachedWaterUiResult(initialStation, limit: 30);
      _loadingStation = _result == null;
      _loadingResult = true;
    }
    unawaited(_loadHomeStation());
  }

  @override
  void dispose() {
    _requestId++;
    unawaited(_resultSubscription?.cancel());
    super.dispose();
  }

  Future<void> _loadHomeStation({bool forceRefresh = false}) async {
    final requestId = ++_requestId;
    await _resultSubscription?.cancel();
    if (mounted) {
      setState(() {
        _loadingStation = _result == null;
        _loadingResult = _station != null;
        _loadFailed = false;
      });
    }

    try {
      final resolvedSelection = await _waterService
          .resolveHomeStationSelection();
      final handedOffStation = _useInitialStation
          ? widget.initialStation
          : null;
      final selection = waterDetailsSelectionForHandoff(
        resolvedSelection,
        handedOffStation,
      );
      if (!mounted || requestId != _requestId) return;
      final station = selection.station;
      final stationChanged = _station?.id != station?.id;
      final cachedResult = station == null
          ? null
          : _waterService.cachedWaterUiResult(station, limit: 30);
      setState(() {
        _selection = selection;
        _station = station;
        if (stationChanged) _result = cachedResult;
        _loadingStation = false;
        _loadingResult = station != null;
        _loadFailed = station == null;
      });
      if (station != null) {
        _listenForResult(
          station,
          requestId,
          forceRefresh || cachedResult != null || _result != null,
        );
      }
    } on Exception {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingStation = false;
        _loadingResult = false;
        _loadFailed = _result == null;
      });
    }
  }

  void _listenForResult(Station station, int requestId, bool forceRefresh) {
    _publishSelectedContext(station);
    _resultSubscription = _waterService
        .getProgressiveWaterUiResults(
          station,
          limit: 30,
          forceRefresh: forceRefresh,
        )
        .listen(
          (result) {
            if (!mounted || requestId != _requestId) return;
            setState(() {
              _result = result;
              _loadingResult = false;
              _loadFailed = false;
            });
          },
          onError: (Object _) {
            if (!mounted || requestId != _requestId) return;
            setState(() {
              _loadingResult = false;
              _loadFailed = _result == null;
            });
          },
          onDone: () {
            if (!mounted || requestId != _requestId) return;
            setState(() => _loadingResult = false);
          },
          cancelOnError: false,
        );
  }

  void _publishSelectedContext(Station station) {
    ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } on StateError {
      return;
    }
    container.read(selectedContextProvider.notifier).publishStation(station);
  }

  void _openAlertEditor() {
    final station = _station;
    if (station == null) return;
    AppNavigator.open(context, AppDestination.newAlert, arguments: station);
  }

  Future<void> _refresh() => _loadHomeStation(forceRefresh: true);

  Future<void> _useAutomaticSelection() async {
    _useInitialStation = false;
    await _waterService.setAutomatic();
    if (mounted) await _loadHomeStation();
  }

  Future<void> _usePinnedSelection(Station station) async {
    _useInitialStation = false;
    final cachedResult = _waterService.cachedWaterUiResult(station, limit: 30);
    if (mounted) {
      setState(() {
        _station = station;
        _result = cachedResult;
        _loadingStation = cachedResult == null;
        _loadingResult = true;
        _loadFailed = false;
      });
    }
    _waterService.selectStation(station);
    if (mounted) await _loadHomeStation();
  }

  Future<void> _openStationSelector() async {
    final selection =
        _selection ??
        WaterHomeStationSelection(
          mode: _waterService.selectionMode,
          station: _waterService.selectedStation,
          candidates: const <Station>[],
        );
    final selected = await showModalBottomSheet<_WaterStationMenuResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) => _WaterStationSelectorSheet(
        selection: selection,
        currentStation: _station,
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.automatic) {
      await _useAutomaticSelection();
    } else if (selected.station != null) {
      await _usePinnedSelection(selected.station!);
    }
  }

  void _selectPeriod(WaterDetailsPeriod period) {
    if (_period == period) return;
    setState(() => _period = period);
  }

  @override
  Widget build(BuildContext context) {
    final station = _station;
    final result = _result;
    final summary = result == null
        ? null
        : WaterDetailsSummary.fromHistory(
            result.history,
            _period,
            stationId: station?.id,
          );

    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      appBar: AppBar(
        title: Text(
          context.l10n.waterLevels,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF07131C),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            key: const Key('water-create-alert-button'),
            tooltip: Localizations.localeOf(context).languageCode == 'ro'
                ? 'Creează alertă'
                : 'Create alert',
            onPressed: station == null ? null : _openAlertEditor,
            icon: const Icon(Icons.add_alert_rounded),
          ),
          IconButton(
            key: const Key('water-station-menu-button'),
            tooltip: 'Alege stația',
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF12D8D6),
              backgroundColor: const Color(0x1F12D8D6),
              side: const BorderSide(color: Color(0x3312D8D6)),
            ),
            onPressed: _openStationSelector,
            icon: const Icon(Icons.menu_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A1C28), Color(0xFF061018)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _loadingStation && result == null
              ? const _WaterDetailsSkeleton()
              : station == null || (_loadFailed && result == null)
              ? _WaterDetailsMessage(onRefresh: _refresh)
              : RefreshIndicator(
                  color: const Color(0xFF12D8D6),
                  onRefresh: _refresh,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final hero = _WaterDetailsHero(
                        station: station,
                        selection: _selection,
                        result: result,
                        isLoading: _loadingResult && result == null,
                        isRefreshing: _loadingResult && result != null,
                        onUseAutomatic: _useAutomaticSelection,
                      );
                      final history = _WaterHistorySection(
                        result: result,
                        summary: summary,
                        period: _period,
                        stationId: station.id,
                        onPeriodSelected: _selectPeriod,
                      );
                      final weather = _StationWeatherPanel(station: station);
                      final landscape =
                          MediaQuery.orientationOf(context) ==
                              Orientation.landscape &&
                          constraints.maxWidth >= 600;
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          landscape ? 20 : 16,
                          16,
                          landscape ? 20 : 16,
                          28,
                        ),
                        children: [
                          if (landscape)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: hero),
                                const SizedBox(width: 14),
                                Expanded(child: history),
                              ],
                            )
                          else ...[
                            hero,
                            const SizedBox(height: 14),
                            history,
                          ],
                          const SizedBox(height: 14),
                          weather,
                        ],
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

class _WaterStationMenuResult {
  const _WaterStationMenuResult.automatic() : automatic = true, station = null;

  const _WaterStationMenuResult.pinned(this.station) : automatic = false;

  final bool automatic;
  final Station? station;
}

class _WaterStationSelectorSheet extends StatefulWidget {
  const _WaterStationSelectorSheet({
    required this.selection,
    required this.currentStation,
  });

  final WaterHomeStationSelection selection;
  final Station? currentStation;

  @override
  State<_WaterStationSelectorSheet> createState() =>
      _WaterStationSelectorSheetState();
}

class _WaterStationSelectorSheetState
    extends State<_WaterStationSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final stations = WaterService.filterStations(
      widget.selection.canonicalStations,
      _query,
    );
    const cyan = Color(0xFF12D8D6);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: landscape ? 0.96 : 0.9,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF07131C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.fromBorderSide(BorderSide(color: Color(0x332BE9E7))),
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 32,
                offset: Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cyan.withValues(alpha: 0.28)),
                      ),
                      child: const Icon(Icons.water_rounded, color: cyan),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stație Water',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Alege automat sau fixează o stație',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Închide',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  key: const Key('water-station-search'),
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  style: const TextStyle(color: Colors.white),
                  cursorColor: cyan,
                  decoration: InputDecoration(
                    hintText: 'Caută stația',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Șterge căutarea',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white54,
                          ),
                    filled: true,
                    fillColor: const Color(0xFF0D202C),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0x332BE9E7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: cyan, width: 1.2),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  children: [
                    _WaterStationTile(
                      key: const Key('water-station-automatic'),
                      title: 'Automat / Locația mea',
                      subtitle: 'Cea mai apropiată stație canonică',
                      icon: Icons.my_location_rounded,
                      selected:
                          widget.selection.mode ==
                          WaterStationSelectionMode.automatic,
                      onTap: () => Navigator.pop(
                        context,
                        const _WaterStationMenuResult.automatic(),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                    if (stations.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'Nicio stație găsită',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    else
                      for (final station in stations)
                        _WaterStationTile(
                          key: Key('water-station-${station.id}'),
                          title: station.name,
                          subtitle:
                              widget.selection.mode ==
                                      WaterStationSelectionMode.pinned &&
                                  station.id == widget.currentStation?.id
                              ? 'Fixat'
                              : station.river.trim().isEmpty
                              ? 'Date Water disponibile'
                              : station.river,
                          icon: Icons.location_on_outlined,
                          selected:
                              widget.selection.mode ==
                                  WaterStationSelectionMode.pinned &&
                              station.id == widget.currentStation?.id,
                          onTap: () => Navigator.pop(
                            context,
                            _WaterStationMenuResult.pinned(station),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaterStationTile extends StatelessWidget {
  const _WaterStationTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  bool get enabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF12D8D6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? const Color(0xFF10313C) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? selected
                            ? cyan
                            : Colors.white60
                      : Colors.white24,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled ? Colors.white : Colors.white30,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled
                              ? Colors.white.withValues(alpha: 0.46)
                              : Colors.white24,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: cyan, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterDetailsHero extends StatelessWidget {
  const _WaterDetailsHero({
    required this.station,
    required this.selection,
    required this.result,
    required this.isLoading,
    required this.isRefreshing,
    required this.onUseAutomatic,
  });

  final Station station;
  final WaterHomeStationSelection? selection;
  final WaterUiResult? result;
  final bool isLoading;
  final bool isRefreshing;
  final Future<void> Function() onUseAutomatic;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final reading = result?.latestReading;
    final canonicalTrend = waterHubCanonicalTrend(result);
    final delta = result?.deltaCm ?? canonicalTrend?.delta?.value;
    final comparisonDuration =
        result?.comparisonDuration ?? canonicalTrend?.delta?.actualInterval;
    final trend = result?.trend ?? canonicalTrend?.trend.displayTrend;
    final comparisonType = reading?.reportedDeltaCm24h != null
        ? WaterComparisonType.daily
        : canonicalTrend?.delta?.comparisonType;
    final color = _trendColor(trend);
    final hasReading = reading != null && reading.value.isFinite;
    final freshnessTimestamp = result?.effectiveFreshnessTimestamp;
    final freshness = freshnessTimestamp == null
        ? context.l10n.updateTimeUnavailable
        : WaterFreshnessFormatter.format(
            freshnessTimestamp: freshnessTimestamp,
            now: DateTime.now(),
            isStale: result!.isStale,
            locale: Localizations.localeOf(context).languageCode,
          );
    final hasProviderError =
        result?.providerError == true ||
        result?.status == WaterUiStatus.providerError;
    final sourceLabel = _sourceLabel(
      result?.source,
      result?.sourceName ?? reading?.sourceName,
    );
    final absoluteLevel = hasReading
        ? '${reading.value.toStringAsFixed(0)} ${reading.unit}'
        : null;

    return _PremiumWaterPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      station.river,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: const Color(0xFF12D8D6),
                      disabledForegroundColor: Colors.white54,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed:
                        selection?.mode == WaterStationSelectionMode.pinned
                        ? onUseAutomatic
                        : null,
                    icon: Icon(
                      selection?.mode == WaterStationSelectionMode.pinned
                          ? Icons.push_pin_rounded
                          : Icons.my_location_rounded,
                      color: selection?.mode == WaterStationSelectionMode.pinned
                          ? const Color(0xFF12D8D6)
                          : Colors.white54,
                    ),
                    label: Text(
                      selection?.mode == WaterStationSelectionMode.pinned
                          ? context.l10n.waterPinned
                          : context.l10n.waterAutomatic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (!hasReading)
            Center(
              child: Text(
                context.l10n.waterUnavailable,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white70),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (delta != null) ...[
                        Text(
                          _formatDelta(delta, reading.unit),
                          key: const Key('water-details-primary-delta'),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          absoluteLevel!,
                          key: const Key('water-details-absolute-level'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: .84),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_comparisonContextLabel(context, comparisonDuration, comparisonType: comparisonType)} · ${_trendLabel(context, trend)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ] else
                        Text(
                          absoluteLevel!,
                          key: const Key('water-details-absolute-level'),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: .36)),
                  ),
                  child: Icon(_trendIcon(trend), color: color, size: 28),
                ),
              ],
            ),
            if (delta == null) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.waterTrendUnavailable,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF9AA7B2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          if (isRefreshing && hasReading) ...[
            const SizedBox(height: 10),
            Text(
              waterDetailsRefreshLabel(context),
              key: const Key('water-details-refresh-label'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF12D8D6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (hasReading && sourceLabel != null) ...[
            _WaterMetadataRow(
              icon: Icons.hub_outlined,
              label: context.l10n.source,
              value: sourceLabel,
            ),
            const SizedBox(height: 8),
          ],
          if (hasReading && result?.measurementTimestamp != null)
            _WaterMetadataRow(
              icon: Icons.schedule_rounded,
              label: context.l10n.lastUpdated,
              value: freshness,
            ),
          if ((!hasReading && hasProviderError) || result?.isStale == true) ...[
            const SizedBox(height: 12),
            _DataStatus(
              isError: hasProviderError,
              message: hasProviderError
                  ? context.l10n.waterProviderUnavailable
                  : context.l10n.waterUnavailable,
            ),
          ],
        ],
      ),
    );
  }
}

class _WaterHistorySection extends StatelessWidget {
  const _WaterHistorySection({
    required this.result,
    required this.summary,
    required this.period,
    required this.stationId,
    required this.onPeriodSelected,
  });

  final WaterUiResult? result;
  final WaterDetailsSummary? summary;
  final WaterDetailsPeriod period;
  final String stationId;
  final ValueChanged<WaterDetailsPeriod> onPeriodSelected;

  @override
  Widget build(BuildContext context) {
    final resolvedSummary = summary;
    final periodTrend = resolvedSummary?.trend;
    final trendColor = _trendColor(periodTrend);
    final hasHistory =
        resolvedSummary != null && resolvedSummary.readings.isNotEmpty;
    final hasChart = resolvedSummary?.hasChart == true;
    return _PremiumWaterPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.waterLevelHistory,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (hasChart)
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _PeriodTrendBadge(
                      coverage: resolvedSummary!.coverage!,
                      delta: resolvedSummary.change!,
                      unit: resolvedSummary.readings.last.unit,
                      trend: periodTrend!,
                      color: trendColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SegmentedButton<WaterDetailsPeriod>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: WaterDetailsPeriod.oneDay,
                  label: Text(
                    waterDetailsPeriodLabel(context, WaterDetailsPeriod.oneDay),
                  ),
                ),
                ButtonSegment(
                  value: WaterDetailsPeriod.threeDays,
                  label: Text(
                    waterDetailsPeriodLabel(
                      context,
                      WaterDetailsPeriod.threeDays,
                    ),
                  ),
                ),
                ButtonSegment(
                  value: WaterDetailsPeriod.sevenDays,
                  label: Text(
                    waterDetailsPeriodLabel(
                      context,
                      WaterDetailsPeriod.sevenDays,
                    ),
                  ),
                ),
                ButtonSegment(
                  value: WaterDetailsPeriod.thirtyDays,
                  label: Text(
                    waterDetailsPeriodLabel(
                      context,
                      WaterDetailsPeriod.thirtyDays,
                    ),
                  ),
                ),
              ],
              selected: {period},
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? const Color(0xFF041318)
                      : Colors.white70,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? const Color(0xFF12D8D6)
                      : const Color(0xFF071923),
                ),
                side: WidgetStateProperty.all(
                  BorderSide(
                    color: const Color(0xFF12D8D6).withValues(alpha: .34),
                  ),
                ),
              ),
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) onPeriodSelected(selection.first);
              },
            ),
          ),
          const SizedBox(height: 16),
          if (!hasHistory)
            _InsufficientHistoryMessage(
              icon: Icons.timeline_rounded,
              message: context.l10n.noWaterData,
            )
          else ...[
            SizedBox(
              height: MediaQuery.orientationOf(context) == Orientation.landscape
                  ? 230
                  : 210,
              width: double.infinity,
              child: _InteractiveWaterHistoryChart(
                readings: resolvedSummary.readings,
                color: trendColor,
                period: period,
              ),
            ),
            const SizedBox(height: 10),
            _RealObservationCaption(summary: resolvedSummary),
            if (!hasChart) ...[
              const SizedBox(height: 12),
              _InsufficientHistoryMessage(
                icon: Icons.info_outline_rounded,
                message: context.l10n.notEnoughHistory,
              ),
            ] else ...[
              const SizedBox(height: 14),
              _HistorySummary(summary: resolvedSummary, color: trendColor),
            ],
          ],
          const SizedBox(height: 16),
          _IntervalDeltaSummary(
            history: result?.history ?? const <WaterLevel>[],
            stationId: stationId,
          ),
        ],
      ),
    );
  }
}

class _RealObservationCaption extends StatelessWidget {
  const _RealObservationCaption({required this.summary});

  final WaterDetailsSummary summary;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final count = summary.readings.length;
    final observations = isRo
        ? '$count ${count == 1 ? 'măsurătoare reală' : 'măsurători reale'}'
        : '$count real ${count == 1 ? 'observation' : 'observations'}';
    final coverage = summary.coverage;
    final coverageLabel = coverage == null
        ? null
        : coverage.inHours < 48
        ? '${coverage.inHours}h'
        : '${coverage.inDays} ${isRo ? 'zile' : 'days'}';

    return Row(
      children: [
        const Icon(Icons.verified_outlined, size: 14, color: Color(0xFF12D8D6)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            coverageLabel == null
                ? observations
                : '$observations · $coverageLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.summary, required this.color});

  final WaterDetailsSummary summary;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final unit = summary.readings.first.unit;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _SummaryValue(
          icon: Icons.south_rounded,
          label: context.l10n.waterHistoryMinimum,
          value: _formatValue(summary.minimum, unit),
        ),
        _SummaryValue(
          icon: Icons.north_rounded,
          label: context.l10n.waterHistoryMaximum,
          value: _formatValue(summary.maximum, unit),
        ),
        _SummaryValue(
          icon: _trendIconFromDelta(summary.change),
          label: _intervalChangeLabel(context),
          value: _formatDelta(summary.change, unit),
          color: color,
        ),
        _SummaryValue(
          icon: Icons.data_usage_rounded,
          label: context.l10n.waterHistoryObservations,
          value: '${summary.readings.length}',
        ),
      ],
    );
  }
}

class _PeriodTrendBadge extends StatelessWidget {
  const _PeriodTrendBadge({
    required this.coverage,
    required this.delta,
    required this.unit,
    required this.trend,
    required this.color,
  });

  final Duration coverage;
  final double delta;
  final String unit;
  final WaterTrend trend;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_trendIcon(trend), size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          '${_compactCoverageLabel(context, coverage)} · '
          '${_formatDelta(delta, unit)}',
          key: const Key('water-details-period-trend-badge'),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

String _compactCoverageLabel(BuildContext context, Duration coverage) {
  final isRo = Localizations.localeOf(context).languageCode == 'ro';
  final minutes = coverage.inMinutes.abs();
  if (minutes < 90) return '${math.max(1, minutes)}m';

  final hours = coverage.inHours.abs();
  if (hours < 72) return '${math.max(1, hours)}h';

  final days = math.max(1, hours ~/ 24);
  return isRo
      ? '$days ${days == 1 ? 'zi' : 'zile'}'
      : '$days ${days == 1 ? 'day' : 'days'}';
}

class _InsufficientHistoryMessage extends StatelessWidget {
  const _InsufficientHistoryMessage({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFF9AA7B2).withValues(alpha: .07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF9AA7B2).withValues(alpha: .18)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF9AA7B2)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _IntervalDeltaSummary extends StatelessWidget {
  const _IntervalDeltaSummary({required this.history, required this.stationId});

  final List<WaterLevel> history;
  final String stationId;

  @override
  Widget build(BuildContext context) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final intervals = <(String, Duration)>[
      ('24h', const Duration(hours: 24)),
      (isRo ? '3 zile' : '3 days', const Duration(days: 3)),
      (isRo ? '7 zile' : '7 days', const Duration(days: 7)),
      (isRo ? '30 zile' : '30 days', const Duration(days: 30)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Localizations.localeOf(context).languageCode == 'ro'
              ? 'COMPARAȚII REALE'
              : 'REAL COMPARISONS',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: intervals
              .map((item) {
                final delta = realWaterIntervalDelta(
                  history,
                  item.$2,
                  stationId: stationId,
                );
                final color = _trendColor(delta?.trend);
                final unit = delta?.to.unit ?? 'cm';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: delta == null ? .04 : .09),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: color.withValues(alpha: .28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.$1,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        delta == null
                            ? context.l10n.notEnoughHistory
                            : _formatDelta(delta.deltaCm, unit),
                        style: TextStyle(
                          color: delta == null ? Colors.white38 : color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color ?? Colors.white54),
      const SizedBox(width: 4),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: Colors.white54,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PremiumWaterPanel extends StatelessWidget {
  const _PremiumWaterPanel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF122B3A), Color(0xFF091A24)],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF12D8D6).withValues(alpha: .38)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF12D8D6).withValues(alpha: .08),
          blurRadius: 22,
          spreadRadius: -12,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: child,
  );
}

class _WaterMetadataRow extends StatelessWidget {
  const _WaterMetadataRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white54, fontSize: 12);
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Colors.white.withValues(alpha: .78),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.15;

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF12D8D6)),
              const SizedBox(width: 8),
              Flexible(child: Text('$label:', style: labelStyle)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: valueStyle,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF12D8D6)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$label:',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          ),
        ),
      ],
    );
  }
}

class _StationWeatherPanel extends StatefulWidget {
  const _StationWeatherPanel({required this.station});

  final Station station;

  @override
  State<_StationWeatherPanel> createState() => _StationWeatherPanelState();
}

class _StationWeatherPanelState extends State<_StationWeatherPanel> {
  final WeatherService _weatherService = WeatherService();
  late Future<WeatherData> _weather;

  @override
  void initState() {
    super.initState();
    _weather = _weatherService.getWeatherForStation(widget.station);
  }

  @override
  void didUpdateWidget(covariant _StationWeatherPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != widget.station.id ||
        oldWidget.station.latitude != widget.station.latitude ||
        oldWidget.station.longitude != widget.station.longitude) {
      _weather = _weatherService.getWeatherForStation(widget.station);
    }
  }

  @override
  Widget build(BuildContext context) => _PremiumWaterPanel(
    padding: const EdgeInsets.all(16),
    child: FutureBuilder<WeatherData>(
      future: _weather,
      builder: (context, snapshot) {
        final weather = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_outlined,
                  color: Color(0xFF12D8D6),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.weather.toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  widget.station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (snapshot.hasError || weather == null)
              Text(
                context.l10n.weatherUnavailable,
                style: const TextStyle(color: Colors.white60),
              )
            else
              Wrap(
                spacing: 18,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _WeatherMetric(
                    icon: Icons.thermostat_rounded,
                    value: '${weather.temperature.round()}°',
                    label: weather.condition,
                  ),
                  _WeatherMetric(
                    icon: Icons.air_rounded,
                    value: '${weather.windSpeed.toStringAsFixed(1)} km/h',
                    label: context.l10n.wind,
                  ),
                  _WeatherMetric(
                    icon: Icons.water_drop_outlined,
                    value: '${weather.humidity.round()}%',
                    label: context.l10n.humidity,
                  ),
                  _WeatherMetric(
                    icon: Icons.speed_rounded,
                    value: weather.pressure == null
                        ? context.l10n.dataUnavailable
                        : '${weather.pressure!.round()} hPa',
                    label: context.l10n.pressure,
                  ),
                ],
              ),
          ],
        );
      },
    ),
  );
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: const Color(0xFF12D8D6)),
      const SizedBox(width: 6),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    ],
  );
}

class _DataStatus extends StatelessWidget {
  const _DataStatus({required this.isError, required this.message});

  final bool isError;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              isError ? Icons.cloud_off_outlined : Icons.schedule_outlined,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractiveWaterHistoryChart extends StatelessWidget {
  const _InteractiveWaterHistoryChart({
    required this.readings,
    required this.color,
    required this.period,
  });

  final List<WaterLevel> readings;
  final Color color;
  final WaterDetailsPeriod period;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) return const SizedBox.shrink();

    final scale = _WaterChartGeometry.scaleBounds(readings, period);
    final bounds = _WaterChartGeometry.timeBounds(readings, period);
    final segments = waterHistoryChartSegments(readings);
    final firstTimestamp = readings.first.timestamp
        .toUtc()
        .millisecondsSinceEpoch
        .toDouble();
    final lastTimestamp = readings.last.timestamp
        .toUtc()
        .millisecondsSinceEpoch
        .toDouble();

    bool showObservationDot(FlSpot spot) {
      if (readings.length <= 10) return true;
      final observation = waterHistoryObservationForTimestamp(segments, spot.x);
      if (observation == null) return false;
      final index = readings.indexOf(observation);
      return index <= 0 || index == readings.length - 1 || index % 4 == 0;
    }

    final bars = <LineChartBarData>[
      for (final segment in segments)
        if (segment.realObservations.isNotEmpty)
          LineChartBarData(
            spots: segment.realObservations
                .map(
                  (reading) => FlSpot(
                    reading.timestamp.toUtc().millisecondsSinceEpoch.toDouble(),
                    reading.value,
                  ),
                )
                .toList(growable: false),
            isCurved: segment.usesBezier,
            curveSmoothness: .12,
            preventCurveOverShooting: true,
            color: color,
            barWidth: segment.hasLine ? 2.6 : 0,
            isStrokeCapRound: true,
            isStrokeJoinRound: true,
            belowBarData: BarAreaData(
              show: segment.usesBezier,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: .18),
                  color.withValues(alpha: .008),
                ],
              ),
            ),
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) => showObservationDot(spot),
              getDotPainter: (spot, _, _, _) {
                final isLatest = spot.x == lastTimestamp;
                final isFirst = spot.x == firstTimestamp;
                return FlDotCirclePainter(
                  radius: isLatest
                      ? 4.2
                      : isFirst
                      ? 3.2
                      : 2.4,
                  color: color,
                  strokeColor: isLatest
                      ? Colors.white.withValues(alpha: .92)
                      : color.withValues(alpha: .18),
                  strokeWidth: isLatest ? 1.4 : 1,
                );
              },
            ),
          ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final yLabels = <String>[
          '${scale.maximum.ceil()} cm',
          '${((scale.minimum + scale.maximum) / 2).round()} cm',
          '${scale.minimum.floor()} cm',
        ];
        final textScaler = MediaQuery.textScalerOf(context);
        double measureLabelWidth(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: _ChartAxisText.textStyle),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          return painter.width;
        }

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 210.0;
        final widestYLabel = yLabels.map(measureLabelWidth).reduce(math.max);
        final yAxisWidth = math.min(availableWidth * .30, widestYLabel + 8);
        final xAxisHeight = math.max(
          18.0,
          textScaler.scale(_ChartAxisText.textStyle.fontSize!) + 8,
        );
        const chartRightPadding = 4.0;
        const chartTopPadding = 6.0;
        final plotWidth = math.max(
          0.0,
          availableWidth - yAxisWidth - chartRightPadding,
        );
        final plotHeight = math.max(
          0.0,
          availableHeight - xAxisHeight - chartTopPadding,
        );
        final showMiddleLabel = plotWidth >= 240;
        final xRange = bounds.maximum - bounds.minimum;
        final midpointX = bounds.minimum + (xRange / 2);
        final includeTime =
            Duration(milliseconds: xRange.round()) <= const Duration(days: 3);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              left: yAxisWidth,
              right: chartRightPadding,
              top: chartTopPadding,
              bottom: xAxisHeight,
              child: LineChart(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                LineChartData(
                  minX: bounds.minimum,
                  maxX: bounds.maximum,
                  minY: scale.minimum,
                  maxY: scale.maximum,
                  clipData: const FlClipData.all(),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  gridData: const FlGridData(show: false),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchSpotThreshold: 22,
                    getTouchedSpotIndicator: (barData, spotIndexes) =>
                        spotIndexes
                            .map(
                              (_) => TouchedSpotIndicatorData(
                                FlLine(
                                  color: color.withValues(alpha: .34),
                                  strokeWidth: 1.1,
                                  dashArray: const [4, 3],
                                ),
                                FlDotData(
                                  getDotPainter: (_, _, _, _) =>
                                      FlDotCirclePainter(
                                        radius: 4.2,
                                        color: color,
                                        strokeColor: Colors.white,
                                        strokeWidth: 1.3,
                                      ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      tooltipMargin: 9,
                      tooltipBorderRadius: BorderRadius.circular(11),
                      tooltipBorder: BorderSide(
                        color: color.withValues(alpha: .38),
                        width: 1,
                      ),
                      getTooltipColor: (_) =>
                          const Color(0xFF07131C).withValues(alpha: .96),
                      getTooltipItems: (touchedSpots) => touchedSpots
                          .map((spot) {
                            final reading = waterHistoryObservationForTimestamp(
                              segments,
                              spot.x,
                            );
                            if (reading == null) return null;
                            final value =
                                reading.value == reading.value.roundToDouble()
                                ? reading.value.toStringAsFixed(0)
                                : reading.value.toStringAsFixed(1);
                            return LineTooltipItem(
                              '$value ${reading.unit}\n',
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${_chartObservationTimeLabel(context, reading)}\n',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                                TextSpan(
                                  text: _readingSourceLabel(reading),
                                  style: TextStyle(
                                    color: color.withValues(alpha: .92),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                  lineBarsData: bars,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: math.max(0, yAxisWidth - 4),
              child: _ChartAxisText(yLabels[0], textAlign: TextAlign.right),
            ),
            Positioned(
              left: 0,
              top: math.max(0, chartTopPadding + (plotHeight / 2) - 5),
              width: math.max(0, yAxisWidth - 4),
              child: _ChartAxisText(yLabels[1], textAlign: TextAlign.right),
            ),
            Positioned(
              left: 0,
              bottom: math.max(0, xAxisHeight - 4),
              width: math.max(0, yAxisWidth - 4),
              child: _ChartAxisText(yLabels[2], textAlign: TextAlign.right),
            ),
            Positioned(
              left: yAxisWidth,
              bottom: 1,
              child: _ChartAxisText(
                _chartAxisLabel(
                  DateTime.fromMillisecondsSinceEpoch(
                    bounds.minimum.round(),
                    isUtc: true,
                  ),
                  includeTime: includeTime,
                ),
              ),
            ),
            if (showMiddleLabel)
              Positioned(
                left: yAxisWidth + (plotWidth / 2) - 36,
                bottom: 1,
                width: 72,
                child: _ChartAxisText(
                  _chartAxisLabel(
                    DateTime.fromMillisecondsSinceEpoch(
                      midpointX.round(),
                      isUtc: true,
                    ),
                    includeTime: includeTime,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Positioned(
              right: chartRightPadding,
              bottom: 1,
              child: _ChartAxisText(
                _chartAxisLabel(
                  DateTime.fromMillisecondsSinceEpoch(
                    bounds.maximum.round(),
                    isUtc: true,
                  ),
                  includeTime: includeTime,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChartAxisText extends StatelessWidget {
  const _ChartAxisText(this.value, {this.textAlign = TextAlign.left});

  static const textStyle = TextStyle(
    color: Color(0x75FFFFFF),
    fontSize: 8.5,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  final String value;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.visible,
    textAlign: textAlign,
    style: textStyle,
  );
}

class _WaterChartGeometry {
  static ({double minimum, double maximum}) scaleBounds(
    List<WaterLevel> readings,
    WaterDetailsPeriod period,
  ) {
    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    final rawRange = maximum - minimum;
    final midpoint = (minimum + maximum) / 2;
    final periodDays = period.duration.inDays;

    final minimumVisualRange = periodDays <= 1
        ? 12.0
        : periodDays <= 3
        ? 18.0
        : periodDays <= 7
        ? 30.0
        : periodDays <= 14
        ? 40.0
        : 50.0;
    final visualRange = math
        .max(minimumVisualRange, rawRange * 1.35)
        .toDouble();

    const axisStep = 5.0;
    final lower =
        ((midpoint - (visualRange / 2)) / axisStep).floor() * axisStep;
    final upper = ((midpoint + (visualRange / 2)) / axisStep).ceil() * axisStep;
    return (minimum: lower, maximum: upper);
  }

  static ({double minimum, double maximum}) timeBounds(
    List<WaterLevel> readings,
    WaterDetailsPeriod period,
  ) {
    final actualMinimum = readings.first.timestamp
        .toUtc()
        .millisecondsSinceEpoch
        .toDouble();
    final maximum = readings.last.timestamp
        .toUtc()
        .millisecondsSinceEpoch
        .toDouble();
    if (readings.length == 1) {
      final padding = math.min(
        const Duration(hours: 12).inMilliseconds.toDouble(),
        math.max(
          const Duration(hours: 1).inMilliseconds.toDouble(),
          period.duration.inMilliseconds * .05,
        ),
      );
      return (minimum: maximum - padding, maximum: maximum + padding);
    }
    final selectedMinimum = maximum - period.duration.inMilliseconds;
    final coverage = maximum - actualMinimum;
    final selectedSpan = period.duration.inMilliseconds.toDouble();
    final sparseCoverage = coverage / selectedSpan < .45;

    if (period.duration > const Duration(days: 1) &&
        (sparseCoverage || readings.length <= 3)) {
      final padding = math.max(
        const Duration(hours: 1).inMilliseconds.toDouble(),
        coverage * .10,
      );
      return (
        minimum: math.max(selectedMinimum, actualMinimum - padding),
        maximum: maximum,
      );
    }

    return (minimum: selectedMinimum, maximum: maximum);
  }
}

class _WaterDetailsSkeleton extends StatelessWidget {
  const _WaterDetailsSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const [
      Card(child: SizedBox(height: 300)),
      SizedBox(height: 16),
      Card(child: SizedBox(height: 280)),
    ],
  );
}

class _WaterDetailsMessage extends StatelessWidget {
  const _WaterDetailsMessage({required this.onRefresh});

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
              const Icon(Icons.water_drop_outlined, size: 48),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(context.l10n.waterUnavailable),
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

Color waterDetailsTrendColor(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => const Color(0xFF2196F3),
  WaterTrend.stable => const Color(0xFF43A047),
  WaterTrend.falling => const Color(0xFFE53935),
  null => const Color(0xFF9AA7B2),
};

Color _trendColor(WaterTrend? trend) => waterDetailsTrendColor(trend);

IconData _trendIcon(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => Icons.trending_up_rounded,
  WaterTrend.stable => Icons.trending_flat_rounded,
  WaterTrend.falling => Icons.trending_down_rounded,
  null => Icons.help_outline_rounded,
};

IconData _trendIconFromDelta(double? delta) => delta == null
    ? Icons.remove_rounded
    : _trendIcon(waterTrendFromRealDelta(delta));

String _trendLabel(BuildContext context, WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => context.l10n.rising,
  WaterTrend.stable => context.l10n.stable,
  WaterTrend.falling => context.l10n.falling,
  null => context.l10n.unknown,
};

String? _sourceLabel(WaterLevelSource? source, String? sourceName) {
  if (sourceName != null &&
      sourceName.trim().isNotEmpty &&
      sourceName != source?.name) {
    return sourceName;
  }
  return switch (source) {
    WaterLevelSource.afdj => 'AFDJ',
    WaterLevelSource.danubeHis => 'DanubeHIS',
    WaterLevelSource.danubeFis => 'DanubeFIS',
    WaterLevelSource.inhga => 'INHGA',
    WaterLevelSource.manualFallback => 'Manual',
    null => null,
  };
}

String _intervalChangeLabel(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ro'
    ? 'Schimbare în interval'
    : 'Change in interval';

String _readingSourceLabel(WaterLevel reading) {
  final sourceName = reading.sourceName.trim();
  if (sourceName.isNotEmpty) return sourceName;
  return switch (reading.source) {
    WaterLevelSource.afdj => 'AFDJ',
    WaterLevelSource.danubeHis => 'DanubeHIS',
    WaterLevelSource.danubeFis => 'DanubeFIS',
    WaterLevelSource.inhga => 'INHGA',
    WaterLevelSource.manualFallback => 'Manual',
  };
}

String _comparisonContextLabel(
  BuildContext context,
  Duration? duration, {
  WaterComparisonType? comparisonType,
}) {
  if (comparisonType == WaterComparisonType.daily ||
      comparisonType == WaterComparisonType.exact24Hours) {
    return context.l10n.waterComparedWithYesterday;
  }
  return context.l10n.waterComparedWithLastReading;
}

String _chartAxisDateLabel(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}';
}

String _chartAxisLabel(DateTime timestamp, {required bool includeTime}) {
  final local = timestamp.toLocal();
  final date = _chartAxisDateLabel(local);
  if (!includeTime) return date;
  return '$date ${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _chartObservationDateLabel(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}

String _chartObservationTimeLabel(
  BuildContext context,
  WaterLevel observation,
) {
  final fullTimestamp = _chartDateTimeLabel(observation.timestamp);
  final isRo = Localizations.localeOf(context).languageCode == 'ro';
  return switch (observation.measurementPrecision) {
    WaterMeasurementPrecision.exact => fullTimestamp,
    WaterMeasurementPrecision.date => _chartObservationDateLabel(
      observation.timestamp,
    ),
    WaterMeasurementPrecision.interval => '$fullTimestamp · interval',
    WaterMeasurementPrecision.relative =>
      '$fullTimestamp · ${isRo ? 'aprox.' : 'approx.'}',
    WaterMeasurementPrecision.unknown =>
      '$fullTimestamp · '
          '${isRo ? 'precizie necunoscut\u0103' : 'unknown precision'}',
  };
}

String _chartDateTimeLabel(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}  '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatValue(double? value, String unit) =>
    value == null ? '—' : '${value.toStringAsFixed(0)} $unit';

String _formatDelta(double? value, String unit) {
  if (value == null) return '—';
  final sign = value > 0 ? '+' : '';
  return '$sign${value.toStringAsFixed(0)} $unit';
}
