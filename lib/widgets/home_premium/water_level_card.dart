import 'dart:async';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/formatters/water_freshness_formatter.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/water/water_history_analysis.dart';
import '../../l10n/l10n.dart';
import '../../models/station.dart';
import '../../models/water_level.dart';
import '../../repositories/water_repository.dart';
import '../../services/water_service.dart';
import 'ai_conditions_card.dart' show PremiumLoadingShimmer;
import 'home_premium_layout.dart';

bool shouldShowWaterLiveBadge({
  required bool hasRealReading,
  required bool isStale,
  required WaterUiStatus status,
  required bool connectivityKnown,
  required bool isDefinitelyOffline,
}) =>
    hasRealReading &&
    !isStale &&
    status != WaterUiStatus.providerError &&
    status != WaterUiStatus.unavailable &&
    connectivityKnown &&
    !isDefinitelyOffline;

String formatWaterCardDelta(double? deltaCm, String unit) {
  if (deltaCm == null || !deltaCm.isFinite) return '—';
  final value = deltaCm == deltaCm.roundToDouble()
      ? deltaCm.toStringAsFixed(0)
      : deltaCm.toStringAsFixed(1);
  final sign = deltaCm > 0 ? '+' : '';
  return '$sign$value $unit';
}

Color waterCardTrendColor(WaterTrend? trend) => switch (trend) {
  WaterTrend.rising => const Color(0xFF2196F3),
  WaterTrend.stable => const Color(0xFF43A047),
  WaterTrend.falling => const Color(0xFFE53935),
  null => const Color(0xFF9AA7B2),
};

bool shouldShowWaterHistoryChart(List<WaterLevel> history) =>
    history.length >= 2;

bool isApproximatelyDailyWaterComparison(Duration duration) {
  final hours = duration.inMinutes.abs() / 60;
  return hours >= 20 && hours <= 28;
}

class WaterLevelCardPremium extends StatefulWidget {
  const WaterLevelCardPremium({
    super.key,
    required this.layout,
    this.selectedStation,
    this.onOpenDetails,
    this.waterService,
  });

  final HomePremiumLayout layout;
  final Station? selectedStation;
  final ValueChanged<Station>? onOpenDetails;
  final WaterService? waterService;

  @override
  State<WaterLevelCardPremium> createState() => _WaterLevelCardPremiumState();
}

class _WaterLevelCardPremiumState extends State<WaterLevelCardPremium> {
  late final WaterService _waterService;
  final Connectivity _connectivity = Connectivity();
  late Future<Station?> _stationFuture;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Station>? _selectionSubscription;
  WaterUiResult? _waterResult;
  String? _waterResultStationId;
  String? _activeStationId;
  bool _isWaterResultLoading = false;
  bool? _isDefinitelyOffline;
  int _stationRequestId = 0;
  WaterStationSelectionMode _selectionMode =
      WaterStationSelectionMode.automatic;

  @override
  void initState() {
    super.initState();
    _waterService = widget.waterService ?? WaterService();
    _stationFuture = Future<Station?>.value(null);
    _isWaterResultLoading = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );
    unawaited(_checkInitialConnectivity());
    _selectionSubscription = _waterService.stationSelections.listen((station) {
      if (mounted) unawaited(_handlePinnedSelection(station));
    });
    unawaited(_initializeFirstPaint());
  }

  @override
  void didUpdateWidget(covariant WaterLevelCardPremium oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedStation?.id != widget.selectedStation?.id) {
      final station = widget.selectedStation;
      if (station != null) unawaited(_handlePinnedSelection(station));
    }
  }

  @override
  void dispose() {
    _stationRequestId++;
    _connectivitySubscription?.cancel();
    _selectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeFirstPaint() async {
    WaterHomeCachedSnapshot? cachedSnapshot;
    try {
      cachedSnapshot = await _waterService.restorePersistedHomeSnapshot();
    } catch (_) {
      // Persistent data is an optimization. Live loading remains authoritative.
    }
    if (!mounted) return;

    final snapshot = cachedSnapshot;
    if (snapshot != null) {
      setState(() {
        _selectionMode = _waterService.selectionMode;
        _activeStationId = snapshot.station.id;
        _waterResultStationId = snapshot.station.id;
        _waterResult = snapshot.result;
        _stationFuture = Future<Station?>.value(snapshot.station);
        _isWaterResultLoading = true;
      });
    }

    await _initializeStationSelection();
  }

  Future<void> _initializeStationSelection() async {
    final selection = await _waterService.resolveHomeStationSelection();
    if (!mounted) return;

    setState(() => _selectionMode = selection.mode);

    final station = selection.station;
    if (station == null) {
      if (_activeStationId == null || _waterResult == null) {
        setState(() {
          _stationFuture = Future<Station?>.value(null);
          _isWaterResultLoading = false;
        });
      } else {
        setState(() => _isWaterResultLoading = false);
      }
      return;
    }

    await _switchStationWhenReady(station, refreshEvenIfActive: true);
  }

  Future<void> _handlePinnedSelection(Station station) async {
    setState(() => _selectionMode = WaterStationSelectionMode.pinned);
    await _switchStationWhenReady(station);
  }

  Future<void> _setAutomatic() async {
    await _waterService.setAutomatic();
    final selection = await _waterService.resolveHomeStationSelection();
    if (!mounted) return;

    setState(() => _selectionMode = selection.mode);

    final station = selection.station;
    if (station != null) {
      await _switchStationWhenReady(station, refreshEvenIfActive: true);
    }
  }

  Future<void> _switchStationWhenReady(
    Station station, {
    bool refreshEvenIfActive = false,
  }) async {
    final alreadyActive = _activeStationId == station.id;
    if (alreadyActive && !refreshEvenIfActive) return;

    final requestId = ++_stationRequestId;
    final cachedResult = _waterService.cachedWaterUiResult(station, limit: 72);
    final stationHasReading = _stationHasUsableReading(station);
    final cachedHasReading = _hasUsableWaterResult(cachedResult);
    final hasDisplayedStation = _activeStationId != null;
    var switchedToRequestedStation =
        alreadyActive ||
        cachedHasReading ||
        stationHasReading ||
        !hasDisplayedStation;

    setState(() {
      _isWaterResultLoading = true;
      if (switchedToRequestedStation) {
        _activeStationId = station.id;
        _waterResultStationId = station.id;
        if (cachedResult != null) {
          _waterResult = cachedResult;
        } else if (!alreadyActive) {
          _waterResult = null;
        }
        _stationFuture = Future<Station?>.value(station);
      }
    });

    try {
      await for (final result in _waterService.getProgressiveWaterUiResults(
        station,
        limit: 72,
        forceRefresh: true,
      )) {
        if (!mounted || requestId != _stationRequestId) return;

        final resultHasReading = _hasUsableWaterResult(result);
        if (!switchedToRequestedStation &&
            !resultHasReading &&
            !stationHasReading) {
          continue;
        }

        setState(() {
          _activeStationId = station.id;
          _waterResultStationId = station.id;
          _stationFuture = Future<Station?>.value(station);

          final currentResultHasReading =
              _waterResultStationId == station.id &&
              _hasUsableWaterResult(_waterResult);
          if (resultHasReading ||
              !currentResultHasReading ||
              stationHasReading) {
            _waterResult = result;
          }
        });
        switchedToRequestedStation = true;
      }
    } catch (_) {
      // Keep the last station-consistent real card visible on request failure.
    } finally {
      if (mounted && requestId == _stationRequestId) {
        setState(() => _isWaterResultLoading = false);
      }
    }
  }

  static bool _stationHasUsableReading(Station station) {
    return station.hasWaterLevel &&
        station.level.isFinite &&
        station.lastUpdate.millisecondsSinceEpoch > 0;
  }

  static bool _hasUsableWaterResult(WaterUiResult? result) {
    final latest = result?.latestReading;
    return latest != null &&
        latest.value.isFinite &&
        latest.timestamp.millisecondsSinceEpoch > 0;
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      _updateConnectivity(await _connectivity.checkConnectivity());
    } on Exception {
      // Keep the badge hidden while connectivity is unknown.
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final isDefinitelyOffline =
        results.isNotEmpty &&
        results.every((result) => result == ConnectivityResult.none);
    if (!mounted || _isDefinitelyOffline == isDefinitelyOffline) return;
    setState(() => _isDefinitelyOffline = isDefinitelyOffline);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Station?>(
      future: _stationFuture,
      builder: (context, snapshot) {
        final snapshotStation = snapshot.data;
        final station = snapshotStation?.id == _activeStationId
            ? snapshotStation
            : null;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final waterResult =
            station != null && _waterResultStationId == station.id
            ? _waterResult
            : null;
        final latestReading = waterResult?.latestReading;
        final hasStationReading = station?.hasWaterLevel == true;
        final hasReading = latestReading != null || hasStationReading;
        final isInitialLoading =
            !hasReading &&
            waterResult == null &&
            !snapshot.hasError &&
            (isLoading || _isWaterResultLoading);
        final waterValue = latestReading?.value ?? station?.level;
        final waterUnit =
            latestReading?.unit ?? station?.waterLevelUnit ?? 'cm';
        final measurementTimestamp =
            waterResult?.measurementTimestamp ??
            (hasStationReading ? station!.lastUpdate : null);
        final measurementAge = measurementTimestamp == null
            ? null
            : DateTime.now().toUtc().difference(measurementTimestamp.toUtc());
        final isStale =
            waterResult?.isStale ??
            (measurementAge != null &&
                measurementAge > WaterRepository.defaultFreshnessThreshold);
        final reliabilityStatus =
            waterResult?.status ??
            (hasReading
                ? WaterUiStatus.insufficientHistory
                : WaterUiStatus.unavailable);
        final hasProviderError =
            reliabilityStatus == WaterUiStatus.providerError;
        final showLiveBadge = shouldShowWaterLiveBadge(
          hasRealReading: hasReading,
          isStale: isStale,
          status: reliabilityStatus,
          connectivityKnown: _isDefinitelyOffline != null,
          isDefinitelyOffline: _isDefinitelyOffline ?? false,
        );
        final showNonLiveBadge = !hasProviderError && (isStale || !hasReading);
        final stationName =
            station?.name ??
            (snapshot.hasError
                ? Localizations.localeOf(context).languageCode == 'ro'
                      ? 'Datele nu pot fi actualizate momentan'
                      : 'Unable to update data right now'
                : isLoading
                ? context.l10n.loadingEllipsis
                : context.l10n.noStationAvailable);
        final waterLevel = hasReading && waterValue != null
            ? '${waterValue.toStringAsFixed(0)} $waterUnit'
            : null;
        final lastUpdate = measurementTimestamp == null
            ? (snapshot.hasError
                  ? Localizations.localeOf(context).languageCode == 'ro'
                        ? 'Încercați din nou în câteva momente'
                        : 'Please try again in a few moments'
                  : null)
            : WaterFreshnessFormatter.format(
                measurementTimestamp: measurementTimestamp,
                now: DateTime.now(),
                isStale: isStale,
                locale: Localizations.localeOf(context).languageCode,
              );
        final sourceLabel = hasReading
            ? _compactSourceName(
                    waterResult?.source ?? latestReading?.source,
                  ) ??
                  latestReading?.sourceName ??
                  station!.waterLevelSource
            : null;

        return PremiumLoadingShimmer(
          isLoading: isInitialLoading,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = widget.layout;
              final narrow = constraints.maxWidth < 340;
              final hasFiniteHeight = constraints.maxHeight.isFinite;
              final compactHeightLimit = layout.isTablet ? 145.0 : 130.0;
              final compact =
                  hasFiniteHeight &&
                  constraints.maxHeight <= compactHeightLimit;
              final cardPadding = layout.isSmallPhone
                  ? 7.0
                  : (layout.isTablet ? 10.0 : 8.0);
              final verticalPadding = (compact ? 5.0 : cardPadding) * .80;
              final fullHistory = waterResult?.history ?? const <WaterLevel>[];
              final baseHistory = realWaterHistorySeries(
                fullHistory,
                period: const Duration(days: 7),
                stationId: station?.id,
              );
              final history = _adaptiveChartHistorySeries(baseHistory);
              final historyLoading =
                  station != null &&
                  _waterResultStationId == station.id &&
                  _isWaterResultLoading;
              final canShowHistory = shouldShowWaterHistoryChart(history);
              final historyDelta = realWaterSeriesDelta(history);
              final historyTrend = waterTrendFromRealDelta(historyDelta);
              final historyColor = waterCardTrendColor(historyTrend);
              const insufficientHistoryColor = Color(0xFF9AA7B2);
              final truthfulTrend =
                  canShowHistory &&
                  historyTrend != null &&
                  historyDelta != null;
              final deltaLabel = formatWaterCardDelta(historyDelta, waterUnit);
              final isRo = Localizations.localeOf(context).languageCode == 'ro';
              final historyComparisonDuration = history.length >= 2
                  ? history.last.timestamp.difference(history.first.timestamp)
                  : waterResult?.comparisonDuration;
              final changeLabel = _changeLabel(
                context,
                historyComparisonDuration,
              );
              final trendStatus = historyTrend == null
                  ? context.l10n.notEnoughHistory
                  : _statusFor(context, historyTrend);
              final badgeLabel = hasReading
                  ? isStale
                        ? (isRo ? 'DATE VECHI' : 'STALE DATA')
                        : (isRo ? 'DATE REALE' : 'LIVE DATA')
                  : (isRo ? 'FĂRĂ DATE' : 'NO DATA');
              final badgeColor = hasReading && !isStale
                  ? const Color(0xFF00BCD4)
                  : Colors.white38;

              if (isInitialLoading) {
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: cardPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF162F40), Color(0xFF0D2230)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.water_drop_rounded,
                            color: const Color(0xFF42A5F5),
                            size: 20 * layout.iconScale,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.l10n.waterLevel.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.cardTitle.copyWith(
                                fontSize:
                                    (compact ? 14 : 16) * layout.titleFontScale,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isRo
                                  ? 'Se \u00eencarc\u0103 nivelul apei\u2026'
                                  : 'Loading water level\u2026',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.white70,
                                fontSize: compact ? 10 : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FractionallySizedBox(
                              widthFactor: .56,
                              child: Container(
                                height: 7,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (!hasReading) {
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: cardPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF162F40), Color(0xFF0D2230)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: const Color(0xFF00BCD4).withValues(alpha: .26),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isRo
                          ? 'Date despre ap\u0103 indisponibile momentan'
                          : 'Water data is temporarily unavailable',
                      key: const Key('water-home-no-data-message'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: station == null || widget.onOpenDetails == null
                      ? null
                      : () => widget.onOpenDetails!(station),
                  child: Ink(
                    padding: EdgeInsets.symmetric(
                      horizontal: cardPadding,
                      vertical: verticalPadding,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF102939), Color(0xFF081B27)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.42),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF00BCD4,
                          ).withValues(alpha: 0.07),
                          blurRadius: 18,
                          spreadRadius: -10,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: compact ? 26 : 30,
                              height: compact ? 26 : 30,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF00BCD4,
                                ).withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(
                                    0xFF00BCD4,
                                  ).withValues(alpha: 0.42),
                                ),
                              ),
                              child: Icon(
                                Icons.water_rounded,
                                color: const Color(0xFF22D3EE),
                                size: (compact ? 15 : 17) * layout.iconScale,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 8),
                            Expanded(
                              child: Text(
                                context.l10n.waterLevel.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.cardTitle.copyWith(
                                  fontSize:
                                      (compact ? 13 : 15) *
                                      layout.titleFontScale,
                                  letterSpacing: .25,
                                ),
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    _selectionMode ==
                                        WaterStationSelectionMode.pinned
                                    ? _setAutomatic
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 6 : 8,
                                    vertical: compact ? 2 : 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .025),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: .13,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _selectionMode ==
                                                WaterStationSelectionMode.pinned
                                            ? Icons.push_pin_rounded
                                            : Icons.my_location_rounded,
                                        color:
                                            _selectionMode ==
                                                WaterStationSelectionMode.pinned
                                            ? const Color(0xFF22D3EE)
                                            : Colors.white54,
                                        size: compact ? 12 : 14,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _selectionMode ==
                                                WaterStationSelectionMode.pinned
                                            ? context.l10n.waterPinned
                                            : context.l10n.waterAutomatic,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.white70,
                                          fontSize: compact ? 8.5 : 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (showLiveBadge || showNonLiveBadge) ...[
                              SizedBox(width: compact ? 4 : 6),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 6 : 7,
                                  vertical: compact ? 2 : 3,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: badgeColor.withValues(alpha: 0.46),
                                  ),
                                ),
                                child: Text(
                                  badgeLabel,
                                  maxLines: 1,
                                  style: AppTextStyles.caption.copyWith(
                                    color: badgeColor,
                                    fontSize: narrow || compact ? 7 : 8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.46,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: compact ? 3 : 5),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: narrow ? 44 : 40,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: compact ? 0 : 1,
                                    right: compact ? 3 : 6,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stationName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.white70,
                                          fontSize: compact ? 11 : 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: compact ? 1 : 2),
                                      Text(
                                        truthfulTrend
                                            ? deltaLabel
                                            : waterLevel!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize:
                                              (truthfulTrend
                                                  ? (compact
                                                        ? 22
                                                        : (narrow ? 25 : 29))
                                                  : (compact
                                                        ? 21
                                                        : (narrow ? 23 : 27))) *
                                              layout.titleFontScale,
                                          height: .98,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -.35,
                                          color: truthfulTrend
                                              ? historyColor
                                              : Colors.white,
                                        ),
                                      ),
                                      if (truthfulTrend && compact) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          changeLabel,
                                          key: const Key(
                                            'water-home-change-label',
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.caption.copyWith(
                                            color: Colors.white54,
                                            fontSize: 8.2,
                                            height: 1,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Row(
                                          children: [
                                            Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: isRo
                                                        ? 'Cota: '
                                                        : 'Level: ',
                                                    style: AppTextStyles.caption
                                                        .copyWith(
                                                          color: Colors.white54,
                                                          fontSize: 8.2,
                                                          height: 1,
                                                        ),
                                                  ),
                                                  TextSpan(
                                                    text: waterLevel!,
                                                    style: AppTextStyles.caption
                                                        .copyWith(
                                                          color: Colors.white,
                                                          fontSize: 9.1,
                                                          height: 1,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              key: const Key(
                                                'water-home-current-level',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.visible,
                                              softWrap: false,
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  Icon(
                                                    _iconFor(historyTrend),
                                                    color: historyColor,
                                                    size: 10.5,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Flexible(
                                                    child: Text(
                                                      trendStatus,
                                                      key: const Key(
                                                        'water-home-trend-status',
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.right,
                                                      style: TextStyle(
                                                        color: historyColor,
                                                        fontSize: 8.6,
                                                        height: 1,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else ...[
                                        if (truthfulTrend) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            changeLabel,
                                            key: const Key(
                                              'water-home-change-label',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                  color: Colors.white54,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text.rich(
                                            TextSpan(
                                              children: [
                                                TextSpan(
                                                  text: isRo
                                                      ? 'Cota actuală: '
                                                      : 'Current level: ',
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                        color: Colors.white54,
                                                        fontSize: 10,
                                                      ),
                                                ),
                                                TextSpan(
                                                  text: waterLevel!,
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            key: const Key(
                                              'water-home-current-level',
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                        ],
                                        Row(
                                          children: [
                                            Icon(
                                              truthfulTrend
                                                  ? _iconFor(historyTrend)
                                                  : Icons.help_outline_rounded,
                                              color: truthfulTrend
                                                  ? historyColor
                                                  : insufficientHistoryColor,
                                              size: 15,
                                            ),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                truthfulTrend
                                                    ? trendStatus
                                                    : context
                                                          .l10n
                                                          .notEnoughHistory,
                                                key: const Key(
                                                  'water-home-trend-status',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: truthfulTrend
                                                      ? historyColor
                                                      : insufficientHistoryColor,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                margin: EdgeInsets.symmetric(
                                  vertical: compact ? 3 : 5,
                                ),
                                color: Colors.white.withValues(alpha: .08),
                              ),
                              SizedBox(width: narrow ? 6 : 8),
                              Expanded(
                                flex: narrow ? 56 : 60,
                                child: Container(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 5 : 7,
                                    compact ? 4 : 5,
                                    compact ? 4 : 6,
                                    compact ? 3 : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        const Color(
                                          0xFF061720,
                                        ).withValues(alpha: .64),
                                        const Color(
                                          0xFF071D29,
                                        ).withValues(alpha: .40),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color:
                                          (canShowHistory
                                                  ? historyColor
                                                  : const Color(0xFF00BCD4))
                                              .withValues(alpha: .19),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      if (canShowHistory)
                                        Positioned(
                                          left: 1,
                                          top: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                              vertical: 1.5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: .12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                            ),
                                            child: Text(
                                              _homeHistoryWindowLabel(
                                                history,
                                                isRo: isRo,
                                              ),
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                    color: Colors.white54,
                                                    fontSize: compact ? 7 : 8.5,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: .25,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      Positioned.fill(
                                        top: canShowHistory
                                            ? (compact ? 10 : 12)
                                            : 0,
                                        child: historyLoading && !canShowHistory
                                            ? const Center(
                                                child: SizedBox.square(
                                                  dimension: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 1.8,
                                                      ),
                                                ),
                                              )
                                            : canShowHistory
                                            ? _WaterHistoryLineChart(
                                                readings: history,
                                                color: historyColor,
                                                unit: waterUnit,
                                                localeCode:
                                                    Localizations.localeOf(
                                                      context,
                                                    ).languageCode,
                                              )
                                            : Center(
                                                child: Text(
                                                  context.l10n.notEnoughHistory,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: AppTextStyles.caption
                                                      .copyWith(
                                                        color: Colors.white38,
                                                        fontSize: compact
                                                            ? 8
                                                            : 9.5,
                                                      ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: compact ? 2 : 4),
                        if (sourceLabel != null || lastUpdate != null)
                          Row(
                            children: [
                              if (sourceLabel != null)
                                Expanded(
                                  child: Text(
                                    '${context.l10n.source}: $sourceLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption.copyWith(
                                      color: Colors.white54,
                                      fontSize: compact ? 8.5 : 10.5,
                                    ),
                                  ),
                                ),
                              if (sourceLabel != null && lastUpdate != null)
                                SizedBox(width: compact ? 6 : 10),
                              if (lastUpdate != null)
                                Flexible(
                                  child: Text(
                                    '${context.l10n.lastUpdated}: $lastUpdate',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: AppTextStyles.caption.copyWith(
                                      color: Colors.white54,
                                      fontSize: compact ? 8.5 : 10.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  static IconData _iconFor(WaterTrend trend) => switch (trend) {
    WaterTrend.rising => Icons.arrow_upward_rounded,
    WaterTrend.stable => Icons.remove_rounded,
    WaterTrend.falling => Icons.arrow_downward_rounded,
  };

  static String _statusFor(BuildContext context, WaterTrend trend) =>
      switch (trend) {
        WaterTrend.rising => context.l10n.rising,
        WaterTrend.stable => context.l10n.stable,
        WaterTrend.falling => context.l10n.falling,
      };

  static String? _compactSourceName(WaterLevelSource? source) =>
      switch (source) {
        WaterLevelSource.afdj => 'AFDJ',
        WaterLevelSource.danubeHis => 'DanubeHIS',
        WaterLevelSource.danubeFis => 'DanubeFIS',
        WaterLevelSource.inhga => 'INHGA',
        WaterLevelSource.manualFallback => 'Manual',
        null => null,
      };

  static String _changeLabel(BuildContext context, Duration? duration) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    if (duration == null) {
      return isRo ? 'Schimbare între citiri' : 'Change between readings';
    }

    final absoluteMinutes = duration.inMinutes.abs();
    if (isApproximatelyDailyWaterComparison(duration)) {
      return isRo ? 'Schimbare în 24h' : '24h change';
    }
    if (absoluteMinutes < 60) {
      final minutes = math.max(1, absoluteMinutes);
      return isRo ? 'Schimbare în $minutes min' : 'Change over $minutes min';
    }

    final hours = (absoluteMinutes / 60).round();
    if (hours < 48) {
      return isRo ? 'Schimbare în ${hours}h' : 'Change over ${hours}h';
    }

    final days = math.max(2, (hours / 24).round());
    return isRo ? 'Schimbare în $days zile' : 'Change over $days days';
  }
}

List<WaterLevel> _adaptiveChartHistorySeries(List<WaterLevel> readings) {
  if (readings.length < 2) return const <WaterLevel>[];

  final latest = readings.last.timestamp;
  for (final duration in const <Duration>[
    Duration(hours: 24),
    Duration(hours: 48),
    Duration(hours: 72),
  ]) {
    final window = readings
        .where(
          (reading) => !reading.timestamp.isBefore(latest.subtract(duration)),
        )
        .toList(growable: false);
    if (window.length >= 2) return window;
  }

  return const <WaterLevel>[];
}

String _homeHistoryWindowLabel(
  List<WaterLevel> readings, {
  required bool isRo,
}) {
  if (readings.length < 2) return '';
  final span = readings.last.timestamp.difference(readings.first.timestamp);
  final window = span <= const Duration(hours: 24)
      ? '24h'
      : span <= const Duration(hours: 48)
      ? '48h'
      : '72h';
  final count = readings.length;
  final observations = isRo
      ? (count == 1 ? 'măsurare' : 'măsurători')
      : (count == 1 ? 'reading' : 'readings');
  return '$window · $count $observations';
}

double _minimumHomeChartVisualRange(double valueRange) {
  if (valueRange <= 2) return 8;
  if (valueRange <= 5) return 12;
  if (valueRange <= 10) return 18;
  if (valueRange <= 20) return 32;
  return valueRange * 1.35;
}

class _WaterHistoryLineChart extends StatelessWidget {
  const _WaterHistoryLineChart({
    required this.readings,
    required this.color,
    required this.unit,
    required this.localeCode,
  });

  final List<WaterLevel> readings;
  final Color color;
  final String unit;
  final String localeCode;

  @override
  Widget build(BuildContext context) {
    if (readings.length < 2) return const SizedBox.shrink();

    final spots = readings
        .map(
          (reading) => FlSpot(
            reading.timestamp.millisecondsSinceEpoch.toDouble(),
            reading.value,
          ),
        )
        .toList(growable: false);
    final rawMinX = spots.first.x;
    final rawMaxX = spots.last.x;
    final xRange = rawMaxX - rawMinX;
    final xPadding = xRange > 0 ? xRange * .06 : 1.0;
    final minX = rawMinX - xPadding;
    final maxX = rawMaxX + xPadding;
    final values = readings
        .map((reading) => reading.value)
        .toList(growable: false);
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final valueRange = maxValue - minValue;
    final visualPadding = math.max(1.5, valueRange * .16);
    final visualRange = math.max(
      valueRange + (visualPadding * 2),
      _minimumHomeChartVisualRange(valueRange),
    );
    final valueMidpoint = (minValue + maxValue) / 2;
    final minY = valueMidpoint - (visualRange / 2);
    final maxY = valueMidpoint + (visualRange / 2);
    final lastIndex = spots.length - 1;

    return LineChart(
      duration: const Duration(milliseconds: 220),
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchSpotThreshold: 18,
          getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
              .map(
                (index) => TouchedSpotIndicatorData(
                  FlLine(
                    color: color.withValues(alpha: .26),
                    strokeWidth: 1.2,
                    dashArray: const [4, 3],
                  ),
                  FlDotData(
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 3.4,
                      color: color,
                      strokeColor: Colors.white,
                      strokeWidth: 1.2,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            tooltipMargin: 8,
            tooltipBorderRadius: BorderRadius.circular(10),
            tooltipBorder: BorderSide(
              color: color.withValues(alpha: .28),
              width: 1,
            ),
            getTooltipColor: (_) =>
                const Color(0xFF081720).withValues(alpha: .94),
            getTooltipItems: (touchedSpots) => touchedSpots
                .map((spot) {
                  final reading = readings[spot.spotIndex];
                  final value = reading.value == reading.value.roundToDouble()
                      ? reading.value.toStringAsFixed(0)
                      : reading.value.toStringAsFixed(1);
                  return LineTooltipItem(
                    '$value $unit\n',
                    TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                    children: [
                      TextSpan(
                        text: _formatChartTimestamp(
                          reading.timestamp.toLocal(),
                          localeCode: localeCode,
                          overallSpan: readings.last.timestamp.difference(
                            readings.first.timestamp,
                          ),
                        ),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                    ],
                  );
                })
                .toList(growable: false),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: valueMidpoint,
              color: Colors.white.withValues(alpha: .06),
              strokeWidth: 1,
              dashArray: const [4, 3],
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: spots.length >= 3,
            curveSmoothness: .18,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.55,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: .24),
                  color.withValues(alpha: .015),
                ],
              ),
            ),
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, barData) =>
                  spots.length <= 8 ||
                  spot.x == spots.first.x ||
                  spot.x == spots[lastIndex].x,
              getDotPainter: (spot, percent, barData, index) {
                final isEdge = index == 0 || index == lastIndex;
                return FlDotCirclePainter(
                  radius: isEdge ? 3.2 : 2.2,
                  color: color,
                  strokeColor: Colors.white.withValues(
                    alpha: isEdge ? .82 : .60,
                  ),
                  strokeWidth: isEdge ? 1.2 : .8,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _formatChartTimestamp(
    DateTime timestamp, {
    required String localeCode,
    required Duration overallSpan,
  }) {
    final hours = timestamp.hour.toString().padLeft(2, '0');
    final minutes = timestamp.minute.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final month = timestamp.month.toString().padLeft(2, '0');
    if (overallSpan.inHours <= 36) {
      return '$hours:$minutes';
    }
    if (localeCode == 'ro') {
      return '$day.$month · $hours:$minutes';
    }
    return '$day/$month · $hours:$minutes';
  }
}
