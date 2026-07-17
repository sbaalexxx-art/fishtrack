import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
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

class _WaterLevelCardPremiumState extends State<WaterLevelCardPremium>
    with WidgetsBindingObserver {
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
  List<Station> _rotationCandidates = const <Station>[];
  Timer? _rotationTimer;
  bool _homeIsActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _waterService = widget.waterService ?? WaterService();
    final lastAutomaticStation = _waterService.lastAutomaticStation;
    _stationFuture = Future<Station?>.value(lastAutomaticStation);
    if (lastAutomaticStation != null) {
      _activeStationId = lastAutomaticStation.id;
      _waterResultStationId = lastAutomaticStation.id;
      _isWaterResultLoading = true;
      unawaited(_loadWaterResult(lastAutomaticStation, ++_stationRequestId));
    } else {
      _isWaterResultLoading = true;
    }
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );
    unawaited(_checkInitialConnectivity());
    _selectionSubscription = _waterService.stationSelections.listen((station) {
      if (mounted) unawaited(_handlePinnedSelection(station));
    });
    unawaited(_initializeStationSelection());
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
    WidgetsBinding.instance.removeObserver(this);
    _stopRotation();
    _connectivitySubscription?.cancel();
    _selectionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _homeIsActive = state == AppLifecycleState.resumed;
    if (_homeIsActive) {
      _startRotationIfNeeded();
    } else {
      _stopRotation();
    }
  }

  Future<void> _initializeStationSelection() async {
    final selection = await _waterService.resolveHomeStationSelection();
    if (!mounted) return;
    setState(() {
      _selectionMode = selection.mode;
      _rotationCandidates = selection.candidates;
      _stationFuture = selection.station == null
          ? Future<Station?>.value(null)
          : _startStationLoad(selection.station);
      if (selection.station == null) _isWaterResultLoading = false;
    });
    _startRotationIfNeeded();
  }

  Future<void> _handlePinnedSelection(Station station) async {
    _stopRotation();
    setState(() => _selectionMode = WaterStationSelectionMode.pinned);
    await _switchStationWhenReady(station);
  }

  Future<void> _setAutomatic() async {
    _stopRotation();
    await _waterService.setAutomatic();
    final selection = await _waterService.resolveHomeStationSelection();
    if (!mounted) return;
    setState(() {
      _selectionMode = selection.mode;
      _rotationCandidates = selection.candidates;
    });
    final station = selection.station;
    if (station != null) await _switchStationWhenReady(station);
    _startRotationIfNeeded();
  }

  void _startRotationIfNeeded() {
    if (!_homeIsActive ||
        _selectionMode != WaterStationSelectionMode.automatic ||
        _rotationCandidates.length < 2 ||
        _rotationTimer != null) {
      return;
    }
    _rotationTimer = Timer.periodic(
      WaterService.homeRotationInterval,
      (_) => unawaited(_rotateStation()),
    );
  }

  void _stopRotation() {
    _rotationTimer?.cancel();
    _rotationTimer = null;
  }

  Future<void> _rotateStation() async {
    if (!_homeIsActive ||
        _selectionMode != WaterStationSelectionMode.automatic ||
        _rotationCandidates.length < 2 ||
        _isWaterResultLoading) {
      return;
    }
    final currentIndex = _rotationCandidates.indexWhere(
      (station) => station.id == _activeStationId,
    );
    final next =
        _rotationCandidates[(currentIndex < 0 ? 0 : currentIndex + 1) %
            _rotationCandidates.length];
    await _switchStationWhenReady(next);
  }

  Future<void> _switchStationWhenReady(Station station) async {
    if (_activeStationId == station.id) return;
    final requestId = ++_stationRequestId;
    setState(() {
      _activeStationId = station.id;
      _waterResult = null;
      _waterResultStationId = station.id;
      _stationFuture = Future<Station?>.value(station);
      _isWaterResultLoading = true;
    });
    try {
      await for (final result in _waterService.getProgressiveWaterUiResults(
        station,
        limit: 72,
        forceRefresh: true,
      )) {
        if (!mounted || requestId != _stationRequestId) return;
        setState(() {
          _activeStationId = station.id;
          _waterResultStationId = station.id;
          _waterResult = result;
          _stationFuture = Future<Station?>.value(station);
        });
      }
    } on Exception {
      // Preserve the current card until a later automatic attempt succeeds.
    } finally {
      if (mounted && requestId == _stationRequestId) {
        setState(() => _isWaterResultLoading = false);
      }
    }
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

  Future<Station?> _startStationLoad(Station? fallbackStation) {
    final requestId = ++_stationRequestId;
    final requestedStationId = fallbackStation?.id;
    if (_activeStationId != requestedStationId) {
      _activeStationId = requestedStationId;
      _waterResult = null;
      _waterResultStationId = null;
    }
    _isWaterResultLoading = true;
    return _loadStation(fallbackStation, requestId);
  }

  Future<Station?> _loadStation(Station? fallbackStation, int requestId) async {
    final station = await _waterService.getNearestStation(
      fallbackStation: fallbackStation,
    );
    if (!mounted || requestId != _stationRequestId) return null;

    if (station == null) {
      setState(() => _isWaterResultLoading = false);
      return null;
    }

    _activeStationId = station.id;
    unawaited(_loadWaterResult(station, requestId));
    return station;
  }

  Future<void> _loadWaterResult(Station station, int requestId) async {
    if (!mounted ||
        requestId != _stationRequestId ||
        _activeStationId != station.id) {
      return;
    }
    setState(() {
      final hasCurrentResult =
          _waterResult != null && _waterResultStationId == station.id;
      if (!hasCurrentResult) _waterResult = null;
      _waterResultStationId = station.id;
      _isWaterResultLoading = true;
    });

    try {
      await for (final result in _waterService.getProgressiveWaterUiResults(
        station,
        limit: 72,
        forceRefresh: true,
      )) {
        if (!mounted ||
            requestId != _stationRequestId ||
            _activeStationId != station.id ||
            _waterResultStationId != station.id) {
          return;
        }
        setState(() => _waterResult = result);
      }
    } on Exception {
      if (!mounted ||
          requestId != _stationRequestId ||
          _activeStationId != station.id ||
          _waterResultStationId != station.id) {
        return;
      }
      _waterResult ??= const WaterUiResult(
        latestReading: null,
        history: [],
        source: null,
        sourceName: null,
        measurementTimestamp: null,
        dataAge: null,
        isStale: false,
        status: WaterUiStatus.providerError,
        safeDiagnosticMessage: 'Water UI request failed',
      );
    }

    if (!mounted ||
        requestId != _stationRequestId ||
        _activeStationId != station.id ||
        _waterResultStationId != station.id) {
      return;
    }

    setState(() => _isWaterResultLoading = false);
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
              final history = realWaterHistorySeries(
                fullHistory,
                period: const Duration(days: 7),
                stationId: station?.id,
              );
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
              final comparisonLabel = _comparisonLabel(
                context,
                waterResult?.comparisonDuration,
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
              final historyTitle = context.l10n.waterLevelHistory.toUpperCase();

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
                        colors: [Color(0xFF162F40), Color(0xFF0D2230)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: const Color(0xFF00BCD4).withValues(alpha: 0.38),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF00BCD4,
                          ).withValues(alpha: 0.06),
                          blurRadius: 16,
                          spreadRadius: -9,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: compact ? 26 : 30,
                              height: compact ? 26 : 30,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF00BCD4,
                                ).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(
                                    0xFF00BCD4,
                                  ).withValues(alpha: 0.46),
                                ),
                              ),
                              child: Icon(
                                Icons.water_rounded,
                                color: const Color(0xFF00BCD4),
                                size: (compact ? 15 : 17) * layout.iconScale,
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 8),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.waterLevel.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.cardTitle.copyWith(
                                      fontSize:
                                          (compact ? 13 : 15) *
                                          layout.titleFontScale,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          stationName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.caption.copyWith(
                                            color: Colors.white70,
                                            fontSize: compact ? 12 : 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: compact ? 2 : 4),
                                      Tooltip(
                                        message: context.l10n.waterStations,
                                        child:
                                            _selectionMode ==
                                                WaterStationSelectionMode.pinned
                                            ? InkResponse(
                                                onTap: _setAutomatic,
                                                radius: 12,
                                                child: Icon(
                                                  Icons.push_pin_rounded,
                                                  color: const Color(
                                                    0xFF00BCD4,
                                                  ),
                                                  size: compact ? 14 : 16,
                                                ),
                                              )
                                            : Icon(
                                                Icons.my_location_rounded,
                                                color: Colors.white54,
                                                size: compact ? 14 : 16,
                                              ),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        _selectionMode ==
                                                WaterStationSelectionMode.pinned
                                            ? context.l10n.waterPinned
                                            : context.l10n.waterAutomatic,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: compact ? 6 : 8),
                            if (showLiveBadge || showNonLiveBadge)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 6.5 : 7.5,
                                  vertical: compact ? 1.5 : 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: badgeColor.withValues(alpha: 0.46),
                                  ),
                                ),
                                child: Text(
                                  badgeLabel,
                                  maxLines: 1,
                                  style: AppTextStyles.caption.copyWith(
                                    color: badgeColor,
                                    fontSize: narrow || compact ? 7.5 : 8.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.48,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: compact ? 2 : 4),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: narrow ? 3 : 4,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            truthfulTrend
                                                ? deltaLabel
                                                : waterLevel!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize:
                                                  (truthfulTrend
                                                      ? (compact
                                                            ? 23
                                                            : (narrow
                                                                  ? 25
                                                                  : 30))
                                                      : (compact
                                                            ? 22
                                                            : (narrow
                                                                  ? 22
                                                                  : 29))) *
                                                  layout.titleFontScale,
                                              height: 1,
                                              fontWeight: FontWeight.bold,
                                              color: truthfulTrend
                                                  ? historyColor
                                                  : Colors.white,
                                            ),
                                          ),
                                        ),
                                        if (truthfulTrend) ...[
                                          SizedBox(width: compact ? 4 : 6),
                                          Flexible(
                                            child: Text(
                                              waterLevel!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                    color: Colors.white70,
                                                    fontSize: compact ? 11 : 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    SizedBox(height: compact ? 1 : 3),
                                    Row(
                                      children: [
                                        Icon(
                                          truthfulTrend
                                              ? _iconFor(historyTrend)
                                              : Icons.help_outline_rounded,
                                          color: truthfulTrend
                                              ? historyColor
                                              : insufficientHistoryColor,
                                          size: compact ? 13 : 16,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            !truthfulTrend
                                                ? context.l10n.notEnoughHistory
                                                : '$deltaLabel · $trendStatus',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: truthfulTrend
                                                  ? historyColor
                                                  : insufficientHistoryColor,
                                              fontSize: compact ? 12 : 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (!compact &&
                                        comparisonLabel != null &&
                                        truthfulTrend) ...[
                                      const SizedBox(height: 1),
                                      Text(
                                        comparisonLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              SizedBox(width: narrow ? 6 : 10),
                              Expanded(
                                flex: narrow ? 2 : 3,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 4 : 6,
                                    vertical: compact ? 2 : 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF061720,
                                    ).withValues(alpha: 0.52),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          (canShowHistory
                                                  ? historyColor
                                                  : const Color(0xFF00BCD4))
                                              .withValues(alpha: 0.20),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        historyTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.white60,
                                          fontSize: narrow || compact ? 7 : 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.55,
                                        ),
                                      ),
                                      SizedBox(height: compact ? 1.5 : 2.5),
                                      Container(
                                        height: 1,
                                        color:
                                            (canShowHistory
                                                    ? historyColor
                                                    : const Color(0xFF00BCD4))
                                                .withValues(alpha: 0.14),
                                      ),
                                      SizedBox(height: compact ? 1.5 : 2.5),
                                      Expanded(
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
                                            ? CustomPaint(
                                                painter: _WaterSparklinePainter(
                                                  readings: history,
                                                  color: historyColor,
                                                ),
                                                child: const SizedBox.expand(),
                                              )
                                            : const SizedBox.shrink(),
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
                                      color: Colors.white60,
                                      fontSize: compact ? 9 : 12,
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
                                      color: Colors.white60,
                                      fontSize: compact ? 9 : 12,
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

  static String? _comparisonLabel(BuildContext context, Duration? duration) {
    if (duration == null) return null;
    return isApproximatelyDailyWaterComparison(duration)
        ? context.l10n.waterComparedWithYesterday
        : context.l10n.waterComparedWithLastReading;
  }
}

class _WaterSparklinePainter extends CustomPainter {
  const _WaterSparklinePainter({required this.readings, required this.color});

  final List<WaterLevel> readings;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.length < 2 || size.isEmpty) return;

    final values = readings.map((reading) => reading.value);
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final valueRange = maximum - minimum;
    final firstTimestamp = readings.first.timestamp.millisecondsSinceEpoch;
    final lastTimestamp = readings.last.timestamp.millisecondsSinceEpoch;
    final timeRange = lastTimestamp - firstTimestamp;
    const inset = 3.0;
    final chartWidth = (size.width - (inset * 2)).clamp(0.0, size.width);
    final chartHeight = (size.height - (inset * 2)).clamp(0.0, size.height);
    final path = Path();
    final points = <Offset>[];

    for (var index = 0; index < readings.length; index++) {
      final reading = readings[index];
      final xFactor = timeRange == 0
          ? index / (readings.length - 1)
          : (reading.timestamp.millisecondsSinceEpoch - firstTimestamp) /
                timeRange;
      final yFactor = valueRange == 0
          ? .5
          : (reading.value - minimum) / valueRange;
      final point = Offset(
        inset + (chartWidth * xFactor),
        inset + chartHeight - (chartHeight * yFactor),
      );
      points.add(point);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height - inset)
      ..lineTo(points.first.dx, size.height - inset)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final lastPoint = points.last;
    canvas.drawCircle(
      lastPoint,
      5,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(lastPoint, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _WaterSparklinePainter oldDelegate) {
    if (oldDelegate.color != color ||
        oldDelegate.readings.length != readings.length) {
      return true;
    }
    for (var index = 0; index < readings.length; index++) {
      final current = readings[index];
      final previous = oldDelegate.readings[index];
      if (current.value != previous.value ||
          current.timestamp != previous.timestamp) {
        return true;
      }
    }
    return false;
  }
}
