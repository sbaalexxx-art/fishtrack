import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/current_location.dart';
import '../../../core/context/selected_context.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/runtime/app_runtime.dart';
import '../../../core/navigation/water_entry.dart';
import '../../../core/theme/fluviai_commercial_tokens.dart';
import '../../../models/station.dart';
import '../../../services/community_service.dart';
import '../../../services/fishing_score_service.dart';
import '../../../services/location_service.dart';
import '../../../services/water_service.dart';
import '../../../services/weather_service.dart';
import '../../../widgets/weather/weather_visuals.dart';
import '../../../widgets/home_premium/home_map.dart';
import '../../../widgets/home_premium/side_menu.dart';
import '../../../widgets/fluviai/draggable_ask_fluvi.dart';
import '../../../screens/developer_mode_page.dart';
import '../../../services/build_mode_service.dart';
import '../../../services/diagnostics_service.dart';
import '../data/commercial_home_data_source.dart';

/// Production Home implementation of the approved Bento contract.
///
/// Presentation follows Figma node 329:11. Runtime data remains sourced from
/// the existing Water, Weather, FluviScore and Community services. The drawer
/// stays wired for existing routes, but the approved Home intentionally has no
/// visible burger button.
class CommercialHomePage extends ConsumerStatefulWidget {
  const CommercialHomePage({
    super.key,
    required this.onNavigate,
    this.onCreateReport,
    this.dataSource,
    this.mapOverride,
    this.accessTier = FluviAccessTier.free,
  });

  final ValueChanged<int> onNavigate;
  final VoidCallback? onCreateReport;
  final CommercialHomeDataSource? dataSource;

  /// Test / integration override. Production renders [HomePremiumMap].
  final Widget? mapOverride;
  final FluviAccessTier accessTier;

  @override
  ConsumerState<CommercialHomePage> createState() => _CommercialHomePageState();
}

class _CommercialHomePageState extends ConsumerState<CommercialHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final HomePremiumMapController _homeMapController =
      HomePremiumMapController();

  late final CommercialHomeDataSource _dataSource;
  late Future<CommercialHomeSnapshot> _snapshotFuture;
  CommercialHomeSnapshot? _progressiveSnapshot;
  int _loadGeneration = 0;
  StreamSubscription<Station>? _stationSelectionSubscription;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? LiveCommercialHomeDataSource();
    _snapshotFuture =
        _dataSource is CurrentLocationAwareCommercialHomeDataSource
        ? Future<CommercialHomeSnapshot>(_loadSnapshot)
        : _loadSnapshot();
    _stationSelectionSubscription = _dataSource.stationSelections.listen((
      station,
    ) {
      if (!mounted) return;
      // The Water service has already pinned this station before emitting the
      // event. Publish cross-module context without recursively selecting it
      // on the same synchronous broadcast controller.
      ref.read(selectedContextProvider.notifier).publishStation(station);
      unawaited(_reload(forceRefresh: true));
    });
  }

  @override
  void dispose() {
    _stationSelectionSubscription?.cancel();
    super.dispose();
  }

  bool get _isRomanian =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';

  Future<void> _reload({bool forceRefresh = false}) async {
    final next = _loadSnapshot(forceRefresh: forceRefresh);
    if (!mounted) return;
    setState(() {
      _snapshotFuture = next;
      if (!forceRefresh) _progressiveSnapshot = null;
    });
    await next;
  }

  Future<CommercialHomeSnapshot> _loadSnapshot({
    bool forceRefresh = false,
  }) async {
    final generation = ++_loadGeneration;
    final languageCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    if (_dataSource
        case final CurrentLocationAwareCommercialHomeDataSource source) {
      final runtime = ref.read(appRuntimeProvider.notifier);
      if (forceRefresh) {
        await runtime.forceRefresh(languageCode: languageCode);
      } else {
        await runtime.start(languageCode: languageCode);
      }
      final locationState = ref.read(currentLocationProvider);
      final location = locationState.location;
      if (locationState.hasUsableLocation && location != null) {
        if (_dataSource case final ProgressiveCommercialHomeDataSource source) {
          final snapshot = await source.loadProgressively(
            location,
            forceRefresh: forceRefresh,
            onUpdate: (snapshot) {
              if (!mounted || generation != _loadGeneration) return;
              _publishAutomaticStationContext(snapshot.station);
              setState(() => _progressiveSnapshot = snapshot);
            },
          );
          if (mounted && generation == _loadGeneration) {
            _publishAutomaticStationContext(snapshot.station);
          }
          return snapshot;
        }
        final snapshot = await source.loadForCurrentLocation(
          location,
          forceRefresh: forceRefresh,
        );
        if (mounted && generation == _loadGeneration) {
          _publishAutomaticStationContext(snapshot.station);
        }
        return snapshot;
      }
    }
    final snapshot = await _dataSource.load(forceRefresh: forceRefresh);
    if (mounted && generation == _loadGeneration) {
      _publishAutomaticStationContext(snapshot.station);
    }
    return snapshot;
  }

  void _openDestination(AppDestination destination, {Object? arguments}) {
    DiagnosticsService.instance.record(
      category: DiagnosticCategory.navigation,
      operation: 'open_destination',
      message: destination.name,
    );
    AppNavigator.open<void>(
      context,
      destination,
      arguments: arguments,
      dataSource: _dataSource,
    );
  }

  void _openDeveloperMode() {
    if (!BuildModeService.isDeveloperVisible) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DeveloperModePage()));
  }

  void _selectStationContext(Station station) {
    ref.read(selectedContextProvider.notifier).selectStation(station);
  }

  void _publishAutomaticStationContext(Station? station) {
    if (station == null) return;
    ref.read(selectedContextProvider.notifier).publishStation(station);
  }

  Future<void> _openWater(CommercialHomeSnapshot? snapshot) async {
    final station = snapshot?.station;
    if (station == null) {
      await AppNavigator.open<Station>(
        context,
        AppDestination.water,
        arguments: const WaterHubRequest(
          entryMode: WaterHubEntryMode.selectStation,
        ),
      );
      return;
    }
    _selectStationContext(station);
    _openDestination(AppDestination.water, arguments: station);
  }

  void _openReport(CommunityPost? report) {
    if (report == null) {
      _openDestination(AppDestination.myReports);
      return;
    }
    _openDestination(AppDestination.reportDetail, arguments: report);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedContextProvider);
    final currentLocationState = ref.watch(currentLocationProvider);
    final providerLocation = currentLocationState.hasUsableLocation
        ? currentLocationState.location
        : null;

    final themeColors = FluviAIThemeColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: themeColors.background,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: themeColors.background,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: themeColors.background,
        drawer: const HomeSideMenu(),
        drawerEnableOpenDragGesture: false,
        body: FutureBuilder<CommercialHomeSnapshot>(
          future: _snapshotFuture,
          builder: (context, snapshotState) {
            final snapshot = _progressiveSnapshot ?? snapshotState.data;
            final loading =
                snapshotState.connectionState == ConnectionState.waiting &&
                snapshot == null;
            return _BentoHomeSurface(
              key: const ValueKey<String>('canonical-home'),
              selected: selected,
              currentLocation: providerLocation ?? snapshot?.currentLocation,
              snapshot: snapshot,
              loading: loading,
              isRomanian: _isRomanian,
              mapController: _homeMapController,
              mapOverride: widget.mapOverride,
              onRefresh: () => _reload(forceRefresh: true),
              onSearch: () => _openDestination(AppDestination.search),
              onLocate: _homeMapController.recenter,
              onAskFluvi: () => _openDestination(AppDestination.askFluvi),
              onNotifications: () =>
                  _openDestination(AppDestination.notifications),
              onDeveloperMode: BuildModeService.isDeveloperVisible
                  ? _openDeveloperMode
                  : null,
              onOpenWater: () => _openWater(snapshot),
              onOpenWeather: () => _openDestination(
                AppDestination.weather,
                arguments: snapshot?.weather,
              ),
              onOpenScore: () => _openDestination(AppDestination.fluvi),
              onOpenCommunity: () => _openDestination(AppDestination.community),
              onOpenReport: _openReport,
            );
          },
        ),
      ),
    );
  }
}

class _BentoHomeSurface extends StatelessWidget {
  const _BentoHomeSurface({
    super.key,
    required this.selected,
    required this.currentLocation,
    required this.snapshot,
    required this.loading,
    required this.isRomanian,
    required this.mapController,
    required this.mapOverride,
    required this.onRefresh,
    required this.onSearch,
    required this.onLocate,
    required this.onAskFluvi,
    required this.onNotifications,
    required this.onDeveloperMode,
    required this.onOpenWater,
    required this.onOpenWeather,
    required this.onOpenScore,
    required this.onOpenCommunity,
    required this.onOpenReport,
  });

  final SelectedContext? selected;
  final CurrentDeviceLocation? currentLocation;
  final CommercialHomeSnapshot? snapshot;
  final bool loading;
  final bool isRomanian;
  final HomePremiumMapController mapController;
  final Widget? mapOverride;
  final Future<void> Function() onRefresh;
  final VoidCallback onSearch;
  final VoidCallback onLocate;
  final VoidCallback onAskFluvi;
  final VoidCallback onNotifications;
  final VoidCallback? onDeveloperMode;
  final VoidCallback onOpenWater;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenScore;
  final VoidCallback onOpenCommunity;
  final ValueChanged<CommunityPost?> onOpenReport;

  String copy({required String ro, required String en}) => isRomanian ? ro : en;

  String get waterLabel {
    final stationName = snapshot?.station?.name.trim();
    if (stationName != null && stationName.isNotEmpty) return stationName;

    final selectedStation = selected?.stationName?.trim();
    if (selectedStation != null && selectedStation.isNotEmpty) {
      return selectedStation;
    }

    final selectedWater = selected?.waterName?.trim();
    if (selectedWater != null && selectedWater.isNotEmpty) return selectedWater;

    final river = snapshot?.station?.river.trim();
    if (river != null && river.isNotEmpty) return river;

    return copy(ro: 'Alege o apă', en: 'Choose water');
  }

  String get placeLabel {
    final currentPlace = homeCurrentLocationLabel(currentLocation);
    if (currentPlace != null && currentPlace.isNotEmpty) return currentPlace;

    return copy(ro: 'Zona ta', en: 'Your area');
  }

  CommunityPost? get activeReport {
    final location = currentLocation;
    if (location == null) return null;
    return selectLocalHomeReport(
      snapshot?.communityPosts ?? const <CommunityPost>[],
      latitude: location.latitude,
      longitude: location.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = (constraints.maxWidth - 32)
              .clamp(0.0, 398.0)
              .toDouble();
          final mapHeight = (contentWidth * 274 / 358).clamp(250.0, 294.0);
          final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final adaptiveTextScale = textScale.clamp(1.0, 2.0).toDouble();
          final scaleDelta = adaptiveTextScale - 1;
          final headerHeight = 40 + scaleDelta * 26;
          // At accessible text sizes the compact Weather card needs more
          // vertical room. QA at 360px / 1.3x measured a 32px intrinsic
          // overflow with the previous +70 slope. Keep the exact 132px
          // canonical height at 1.0x, then expand the row only as Dynamic
          // Type grows; Home is scrollable, so accessibility wins over
          // forcing scaled text into the 1.0x card height.
          final waterRowHeight = 132 + scaleDelta * 210;
          final decisionRowHeight = 100 + scaleDelta * 56;
          final reportHeight = 100 + scaleDelta * 50;

          return RefreshIndicator.adaptive(
            onRefresh: onRefresh,
            color: FluviAICommercialTokens.brandFocus,
            backgroundColor: FluviAIThemeColors.of(context).surface,
            child: SingleChildScrollView(
              key: const PageStorageKey<String>('canonical-home-scroll'),
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BentoHeader(
                        height: headerHeight,
                        placeLabel: placeLabel,
                        isRomanian: isRomanian,
                        onNotifications: onNotifications,
                        onDeveloperMode: onDeveloperMode,
                      ),
                      const SizedBox(height: 1),
                      SizedBox(
                        height: mapHeight,
                        child: _BentoMapCard(
                          controller: mapController,
                          mapOverride: mapOverride,
                          isRomanian: isRomanian,
                          onSearch: onSearch,
                          onLocate: onLocate,
                          onAskFluvi: onAskFluvi,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: waterRowHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 230,
                              child: _BentoWaterCard(
                                snapshot: snapshot,
                                waterLabel: waterLabel,
                                loading:
                                    snapshot?.waterStatus ==
                                        CommercialHomeDomainStatus.loading ||
                                    (snapshot == null && loading),
                                isRomanian: isRomanian,
                                onTap: onOpenWater,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 120,
                              child: _BentoWeatherCard(
                                weather: snapshot?.weather,
                                loading:
                                    snapshot?.weatherStatus ==
                                        CommercialHomeDomainStatus.loading ||
                                    (snapshot == null && loading),
                                isRomanian: isRomanian,
                                onTap: onOpenWeather,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: decisionRowHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 110,
                              child: _BentoFluviCard(
                                score: snapshot?.score,
                                loading:
                                    snapshot?.scoreStatus ==
                                        CommercialHomeDomainStatus.loading ||
                                    (snapshot == null && loading),
                                isRomanian: isRomanian,
                                onTap: onOpenScore,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 240,
                              child: _BentoCommunityCard(
                                posts: filterLocalHomePosts(
                                  snapshot?.communityPosts ??
                                      const <CommunityPost>[],
                                  latitude: currentLocation?.latitude,
                                  longitude: currentLocation?.longitude,
                                ),
                                loading:
                                    snapshot?.communityStatus ==
                                        CommercialHomeDomainStatus.loading ||
                                    (snapshot == null && loading),
                                isRomanian: isRomanian,
                                onTap: onOpenCommunity,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: reportHeight,
                        child: _BentoReportCard(
                          report: activeReport,
                          currentLocation: currentLocation,
                          loading:
                              snapshot?.communityStatus ==
                                  CommercialHomeDomainStatus.loading ||
                              (snapshot == null && loading),
                          isRomanian: isRomanian,
                          onTap: () => onOpenReport(activeReport),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String? homeCurrentLocationLabel(CurrentDeviceLocation? location) {
  final label = location?.label?.trim();
  return label == null || label.isEmpty ? null : label;
}

class _BentoHeader extends StatelessWidget {
  const _BentoHeader({
    required this.height,
    required this.placeLabel,
    required this.isRomanian,
    required this.onNotifications,
    required this.onDeveloperMode,
  });

  final double height;
  final String placeLabel;
  final bool isRomanian;
  final VoidCallback onNotifications;
  final VoidCallback? onDeveloperMode;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 245),
                child: Semantics(
                  label: isRomanian
                      ? 'Locatia fizica actuala'
                      : 'Current physical location',
                  button: onDeveloperMode != null,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('commercial-home-context-header'),
                      onLongPress: onDeveloperMode,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: colors.surfaceStrong.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.borderSoft.withValues(alpha: .72),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: FluviAICommercialTokens.brandFocus,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                placeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily:
                                      FluviAICommercialTokens.primaryFontFamily,
                                  color: colors.textPrimary,
                                  fontSize: 12.5,
                                  height: 16 / 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            label: isRomanian ? 'Notificari' : 'Notifications',
            button: true,
            child: SizedBox(
              key: const ValueKey('canonical-home-alerts'),
              width: 40,
              height: 40,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onNotifications,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surfaceStrong.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colors.borderSoft.withValues(alpha: .72),
                        ),
                      ),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        size: 15,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoMapCard extends StatelessWidget {
  const _BentoMapCard({
    required this.controller,
    required this.mapOverride,
    required this.isRomanian,
    required this.onSearch,
    required this.onLocate,
    required this.onAskFluvi,
  });

  final HomePremiumMapController controller;
  final Widget? mapOverride;
  final bool isRomanian;
  final VoidCallback onSearch;
  final VoidCallback onLocate;
  final VoidCallback onAskFluvi;

  @override
  Widget build(BuildContext context) {
    final map = mapOverride == null
        ? HomePremiumMap(
            key: const ValueKey('commercial-home-map'),
            controller: controller,
            embedded: true,
            showControls: false,
          )
        : KeyedSubtree(
            key: const ValueKey('commercial-home-map'),
            child: mapOverride!,
          );

    return Container(
      key: const ValueKey('commercial-home-map-hero'),
      decoration: BoxDecoration(
        color: FluviAIThemeColors.of(context).backgroundRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: map),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: FluviAIThemeColors.of(context).border,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .12),
                      Colors.transparent,
                      Colors.black.withValues(alpha: .18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 18,
            child: Row(
              children: [
                _BentoMapButton(
                  key: const ValueKey('home-map-search'),
                  icon: Icons.search_rounded,
                  tooltip: isRomanian ? 'Caută' : 'Search',
                  onTap: onSearch,
                ),
                const SizedBox(width: 8),
                _BentoMapButton(
                  key: const ValueKey('home-map-locate'),
                  icon: Icons.my_location_rounded,
                  tooltip: isRomanian ? 'Locația mea' : 'My location',
                  onTap: onLocate,
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: DraggableAskFluviControl(
              controlKey: const ValueKey('home-ask-fluvi'),
              scope: AskFluviPlacementScope.home,
              controlSize: const Size(48, 48),
              defaultNormalizedPosition: const Offset(1, 1),
              workspaceBuilder: (size) =>
                  Rect.fromLTRB(12, 12, size.width - 12, size.height - 16),
              obstaclesBuilder: (size) => <Rect>[
                Rect.fromLTWH(12, size.height - 62, 96, 44),
              ],
              semanticLabel: isRomanian ? 'Întreabă Fluvi' : 'Ask Fluvi',
              onTap: onAskFluvi,
              child: Center(
                child: Material(
                  color: FluviAIThemeColors.of(context).surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: onAskFluvi,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _BentoColors.accentBorder),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        size: 20,
                        color: _BentoColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
class HomeWaterSemanticPresentation {
  const HomeWaterSemanticPresentation({required this.primary, this.secondary});

  final String primary;
  final String? secondary;
}

WaterTrend? resolvedHomeWaterTrend(WaterUiResult? water) =>
    water?.trend ?? water?.effectiveCanonicalTrend?.trend.displayTrend;

HomeWaterSemanticPresentation resolveHomeWaterSemanticPresentation({
  required double? dailyDelta,
  required WaterTrend? trend,
  required bool isRomanian,
}) {
  final hasDelta = dailyDelta != null && dailyDelta.isFinite;
  final trendLabel = _waterVerdict(trend, isRomanian: isRomanian);
  final insufficientDelta = isRomanian
      ? 'Date insuficiente pentru Δ24h'
      : 'Insufficient data for Δ24h';
  if (hasDelta && trend != null) {
    return HomeWaterSemanticPresentation(
      primary: '${_signedNumber(dailyDelta)} cm / 24h · $trendLabel',
    );
  }
  if (hasDelta) {
    return HomeWaterSemanticPresentation(
      primary: '${_signedNumber(dailyDelta)} cm / 24h',
      secondary: trendLabel,
    );
  }
  return HomeWaterSemanticPresentation(
    primary: trend == null
        ? trendLabel
        : '${isRomanian ? 'Trend' : 'Trend'} ${trendLabel.toLowerCase()}',
    secondary: insufficientDelta,
  );
}

class _BentoWaterCard extends StatelessWidget {
  const _BentoWaterCard({
    required this.snapshot,
    required this.waterLabel,
    required this.loading,
    required this.isRomanian,
    required this.onTap,
  });

  final CommercialHomeSnapshot? snapshot;
  final String waterLabel;
  final bool loading;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final water = snapshot?.water;
    final reading = water?.latestReading;
    final trend = resolvedHomeWaterTrend(water);
    final delta = water?.deltaCm;
    final trendColor = _waterTrendColor(context, trend);
    final value = reading == null ? '—' : _formatNumber(reading.value);
    final unit = reading?.unit ?? snapshot?.station?.waterLevelUnit ?? 'cm';

    final comparison = water?.comparisonDuration;
    final hasDailyComparison =
        comparison != null &&
        comparison.inHours >= 18 &&
        comparison.inHours <= 30;
    final dailyDelta = hasDailyComparison && delta != null && delta.isFinite
        ? delta
        : null;
    final semantic = resolveHomeWaterSemanticPresentation(
      dailyDelta: dailyDelta,
      trend: trend,
      isRomanian: isRomanian,
    );

    final rawSource = water?.sourceName?.trim().isNotEmpty == true
        ? water!.sourceName!.trim()
        : reading?.sourceName.trim().isNotEmpty == true
        ? reading!.sourceName.trim()
        : snapshot?.station?.waterLevelSource.trim().isNotEmpty == true
        ? snapshot!.station!.waterLevelSource.trim()
        : (isRomanian ? 'sursă indisponibilă' : 'source unavailable');
    final source = _homeSourceLabel(rawSource);

    final age = water?.dataAge;
    final freshness = age == null
        ? source
        : '$source · ${_homeFreshnessAge(age, isRomanian: isRomanian)}';

    return _BentoCardTap(
      key: const ValueKey('commercial-water-card'),
      onTap: onTap,
      radius: 18,
      color: FluviAIThemeColors.of(context).surfaceRaised,
      child: loading
          ? const _BentoSkeleton(lines: [94, 70, 134, 150])
          : Padding(
              padding: const EdgeInsets.fromLTRB(13, 8, 11, 7),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _BentoColors.waterBlue.withValues(alpha: .16),
                              FluviAIThemeColors.of(
                                context,
                              ).surfaceRaised.withValues(alpha: .05),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -38,
                    right: -28,
                    width: 116,
                    height: 116,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _BentoColors.waterBlue.withValues(alpha: .15),
                              _BentoColors.waterBlue.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.water_drop_outlined,
                              size: 15,
                              color: _BentoColors.waterBlue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                waterLabel,
                                key: const ValueKey('home-water-station-name'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily:
                                      FluviAICommercialTokens.monoFontFamily,
                                  color: FluviAIThemeColors.of(
                                    context,
                                  ).textSecondary,
                                  fontSize: 12.5,
                                  height: 15 / 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [snapshot?.station?.river.trim(), source]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FluviAICommercialTokens.monoFontFamily,
                            color: FluviAIThemeColors.of(context).textMuted,
                            fontSize: 8.5,
                            height: 10.2 / 8.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    fontFamily: FluviAICommercialTokens
                                        .primaryFontFamily,
                                    color: FluviAIThemeColors.of(
                                      context,
                                    ).textPrimary,
                                    fontSize: 29,
                                    height: 31 / 29,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (reading != null) ...[
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  unit,
                                  style: TextStyle(
                                    fontFamily: FluviAICommercialTokens
                                        .primaryFontFamily,
                                    color: FluviAIThemeColors.of(
                                      context,
                                    ).textSecondary,
                                    fontSize: 13,
                                    height: 15.6 / 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          semantic.primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: trendColor,
                            fontSize: 10.5,
                            height: 12.6 / 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (semantic.secondary != null)
                          Text(
                            semantic.secondary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily:
                                  FluviAICommercialTokens.primaryFontFamily,
                              color: FluviAIThemeColors.of(
                                context,
                              ).textSecondary,
                              fontSize: 8.5,
                              height: 10.2 / 8.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        const Spacer(),
                        Text(
                          freshness,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: FluviAIThemeColors.of(context).textMuted,
                            fontSize: 8.5,
                            height: 10.2 / 8.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    top: 42,
                    right: 0,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _BentoColors.accent,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BentoWeatherCard extends StatelessWidget {
  const _BentoWeatherCard({
    required this.weather,
    required this.loading,
    required this.isRomanian,
    required this.onTap,
  });

  final WeatherHomeResult? weather;
  final bool loading;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = weather?.data;
    final theme = Theme.of(context);
    final kind = weatherVisualKind(data?.condition ?? '');
    final daylight = data == null ? true : weatherIsDaylight(data);
    final accent = data == null
        ? FluviAIThemeColors.of(context).textSecondary
        : weatherVisualAccent(
            kind,
            isDaylight: daylight,
            brightness: theme.brightness,
          );
    final gradient = data == null
        ? <Color>[
            FluviAIThemeColors.of(context).surface,
            FluviAIThemeColors.of(context).surface,
          ]
        : weatherAtmosphereGradient(
            kind,
            isDaylight: daylight,
            brightness: theme.brightness,
          );

    final onAtmosphere =
        data != null && (theme.brightness == Brightness.dark || !daylight)
        ? Colors.white
        : FluviAIThemeColors.of(context).textPrimary;
    final secondary = onAtmosphere.withValues(alpha: .70);

    return _BentoCardTap(
      key: const ValueKey('commercial-weather-card'),
      onTap: onTap,
      radius: 18,
      color: FluviAIThemeColors.of(context).surface,
      child: loading
          ? const _BentoSkeleton(lines: [64, 54, 86, 76])
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (data != null)
                    Positioned.fill(
                      child: WeatherAtmosphereBackdrop(
                        kind: kind,
                        isDaylight: daylight,
                        foreground: onAtmosphere,
                        compact: true,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 11, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              child: Icon(
                                data == null
                                    ? Icons.cloud_outlined
                                    : weatherVisualIcon(
                                        kind,
                                        isDaylight: daylight,
                                      ),
                                key: ValueKey<String>('${kind.name}-$daylight'),
                                size: 19,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                isRomanian ? 'VREME' : 'WEATHER',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontFamily:
                                      FluviAICommercialTokens.monoFontFamily,
                                  color: secondary,
                                  fontSize: 9,
                                  height: 10.8 / 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              data == null
                                  ? '—'
                                  : '${data.temperature.round()}°',
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily:
                                    FluviAICommercialTokens.primaryFontFamily,
                                color: onAtmosphere,
                                fontSize: 31,
                                height: 37.2 / 31,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (data != null)
                          Text(
                            weatherConditionLabel(
                              data.condition,
                              isRomanian: isRomanian,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily:
                                  FluviAICommercialTokens.primaryFontFamily,
                              color: onAtmosphere,
                              fontSize: 10.5,
                              height: 12.6 / 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Text(
                            isRomanian
                                ? 'Date indisponibile'
                                : 'Data unavailable',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily:
                                  FluviAICommercialTokens.primaryFontFamily,
                              color: secondary,
                              fontSize: 10,
                            ),
                          ),
                        const Spacer(),
                        if (data != null)
                          Row(
                            children: [
                              Icon(
                                Icons.air_rounded,
                                size: 12,
                                color: secondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${_localizedWindDirection(data.windDirectionLabel, isRomanian: isRomanian)} '
                                    '${data.windSpeed.round()} km/h',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontFamily: FluviAICommercialTokens
                                          .primaryFontFamily,
                                      color: secondary,
                                      fontSize: 9.5,
                                      height: 11.4 / 9.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                Icons.water_drop_outlined,
                                size: 12,
                                color: secondary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${data.precipitationProbability.round()}%',
                                style: TextStyle(
                                  fontFamily:
                                      FluviAICommercialTokens.primaryFontFamily,
                                  color: secondary,
                                  fontSize: 9.5,
                                  height: 11.4 / 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BentoFluviCard extends StatelessWidget {
  const _BentoFluviCard({
    required this.score,
    required this.loading,
    required this.isRomanian,
    required this.onTap,
  });

  final FishingScoreResult? score;
  final bool loading;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = score?.score;
    return _BentoCardTap(
      key: const ValueKey('commercial-score-card'),
      onTap: onTap,
      radius: 18,
      color: FluviAIThemeColors.of(context).surfaceStrong,
      child: loading
          ? const _BentoSkeleton(lines: [54, 48, 76])
          : Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: _BentoColors.accent,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'FLUVI',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontFamily: FluviAICommercialTokens.monoFontFamily,
                            color: FluviAIThemeColors.of(context).textSecondary,
                            fontSize: 9,
                            height: 10.8 / 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height:
                        MediaQuery.textScalerOf(context).scale(27) *
                        (32.4 / 27),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value == null ? '\u2014' : value.round().toString(),
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily:
                                  FluviAICommercialTokens.primaryFontFamily,
                              color: FluviAIThemeColors.of(context).textPrimary,
                              fontSize: 27,
                              height: 32.4 / 27,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (value != null)
                          Positioned(
                            left: 44,
                            right: 0,
                            bottom: 4,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.bottomLeft,
                              child: const Text(
                                '/100',
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily:
                                      FluviAICommercialTokens.primaryFontFamily,
                                  color: _BentoColors.accent,
                                  fontSize: 10.5,
                                  height: 12 / 10.5,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _scoreVerdict(score?.rating, isRomanian: isRomanian),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FluviAICommercialTokens.primaryFontFamily,
                      color: _scoreColor(context, score?.rating),
                      fontSize: 11,
                      height: 13.2 / 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BentoCommunityCard extends StatelessWidget {
  const _BentoCommunityCard({
    required this.posts,
    required this.loading,
    required this.isRomanian,
    required this.onTap,
  });

  final List<CommunityPost> posts;
  final bool loading;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final recent = posts
        .where(
          (post) =>
              post.type == CommunityPostType.catchPost &&
              now.difference(post.createdAt).abs() <= const Duration(hours: 2),
        )
        .toList(growable: false);
    final latest = recent.isNotEmpty
        ? (recent.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
              .first
        : null;

    final title = latest?.title.trim().isNotEmpty == true
        ? latest!.title.trim()
        : isRomanian
        ? 'Fără semnal local recent'
        : 'No recent local signal';
    final detail = recent.isEmpty
        ? (isRomanian ? '0 actualizări · 2h' : '0 updates · 2h')
        : '${recent.length} ${isRomanian ? 'actualizări' : 'updates'} · 2h';

    return _BentoCardTap(
      key: const ValueKey('commercial-community-card'),
      onTap: onTap,
      radius: 18,
      color: FluviAIThemeColors.of(context).surfaceRaised,
      child: loading
          ? const _BentoSkeleton(lines: [108, 190, 160])
          : Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.group_outlined,
                              size: 19,
                              color: FluviAIThemeColors.of(
                                context,
                              ).textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isRomanian ? 'PULS LOCAL' : 'LOCAL PULSE',
                              style: TextStyle(
                                fontFamily:
                                    FluviAICommercialTokens.monoFontFamily,
                                color: FluviAIThemeColors.of(
                                  context,
                                ).textSecondary,
                                fontSize: 9,
                                height: 10.8 / 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: FluviAIThemeColors.of(context).textPrimary,
                            fontSize: 15,
                            height: 18 / 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: FluviAIThemeColors.of(context).textMuted,
                            fontSize: 10,
                            height: 12 / 10,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    top: 30,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _BentoColors.accent,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

String localizedHomeReportCategory(
  ReportCategory category, {
  required bool isRomanian,
}) {
  if (!isRomanian) return category.label;
  return switch (category) {
    ReportCategory.fishActivity => 'Activitate pește',
    ReportCategory.waterClarity => 'Claritatea apei',
    ReportCategory.floatingGrass => 'Vegetație plutitoare',
    ReportCategory.highWater => 'Apă ridicată',
    ReportCategory.lowWater => 'Apă scăzută',
    ReportCategory.strongCurrent => 'Curent puternic',
    ReportCategory.noCurrent => 'Fără curent',
    ReportCategory.boats => 'Ambarcațiuni',
    ReportCategory.poaching => 'Braconaj',
    ReportCategory.theftWarning => 'Avertizare furt',
    ReportCategory.accessBlocked => 'Acces blocat',
    ReportCategory.parkingAvailable => 'Parcare disponibilă',
    ReportCategory.goodFishing => 'Pescuit bun',
    ReportCategory.poorFishing => 'Pescuit slab',
    ReportCategory.other => 'Altă observație',
  };
}

class _BentoReportCard extends StatelessWidget {
  const _BentoReportCard({
    required this.report,
    required this.currentLocation,
    required this.loading,
    required this.isRomanian,
    required this.onTap,
  });

  final CommunityPost? report;
  final CurrentDeviceLocation? currentLocation;
  final bool loading;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = report;
    final age = item == null
        ? null
        : DateTime.now().difference(item.createdAt).abs();
    final distance = item == null || currentLocation == null
        ? null
        : _distanceKm(
            currentLocation!.latitude,
            currentLocation!.longitude,
            item.latitude,
            item.longitude,
          );

    final label = item == null
        ? (isRomanian ? 'RAPOARTE LOCALE' : 'LOCAL REPORTS')
        : '${isRomanian ? 'RAPORT ACTIV' : 'ACTIVE REPORT'} · ${_relativeAge(age ?? Duration.zero, isRomanian: isRomanian).toUpperCase()}';

    final categoryTitle = item?.reportCategory == null
        ? null
        : localizedHomeReportCategory(
            item!.reportCategory!,
            isRomanian: isRomanian,
          );
    final rawTitle = item?.title.trim();
    final title =
        categoryTitle ??
        (rawTitle != null &&
                rawTitle.isNotEmpty &&
                !(isRomanian && rawTitle.toLowerCase() == 'other')
            ? rawTitle
            : (isRomanian ? 'Niciun raport activ' : 'No active report'));

    final details = <String>[
      if (distance != null)
        '${distance.toStringAsFixed(1).replaceAll('.', ',')} km',
      if (item != null)
        '${item.stillValidCount} ${isRomanian ? 'confirmări' : 'confirmations'}',
    ];
    final detail = details.isEmpty
        ? (isRomanian
              ? 'Vezi arhiva și rapoartele din zonă'
              : 'Open reports for this area')
        : details.join(' · ');

    return _BentoCardTap(
      key: const ValueKey('commercial-reports-card'),
      onTap: onTap,
      radius: 18,
      color: FluviAIThemeColors.of(context).surface,
      child: loading
          ? const _BentoSkeleton(lines: [164, 198, 190])
          : Padding(
              padding: const EdgeInsets.fromLTRB(13, 13, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        _BentoColors.warning.withValues(alpha: .10),
                        FluviAIThemeColors.of(context).surfaceRaised,
                      ),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _BentoColors.warningBorder),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: _BentoColors.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FluviAICommercialTokens.monoFontFamily,
                            color: FluviAIThemeColors.of(context).textSecondary,
                            fontSize: 9,
                            height: 10.8 / 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: FluviAIThemeColors.of(context).textPrimary,
                            fontSize: 16,
                            height: 19.2 / 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: FluviAIThemeColors.of(context).textSecondary,
                            fontSize: 11,
                            height: 13.2 / 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: _BentoColors.accent,
                  ),
                ],
              ),
            ),
    );
  }
}

class _BentoMapButton extends StatelessWidget {
  const _BentoMapButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: FluviAIThemeColors.of(context).surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: FluviAIThemeColors.of(context).border,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: FluviAIThemeColors.of(context).textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BentoCardTap extends StatelessWidget {
  const _BentoCardTap({
    super.key,
    required this.onTap,
    required this.radius,
    required this.color,
    required this.child,
  });

  final VoidCallback onTap;
  final double radius;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: FluviAIThemeColors.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class _BentoSkeleton extends StatelessWidget {
  const _BentoSkeleton({required this.lines});

  final List<double> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < lines.length; index++) ...[
            Container(
              width: lines[index],
              height: index == 1 ? 26 : 10,
              decoration: BoxDecoration(
                color: FluviAIThemeColors.of(context).surfaceStrong,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (index != lines.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

abstract final class _BentoColors {
  static const accent = Color(0xFF43D9CC);
  static const accentBorder = Color(0x7343D9CC);
  static const warning = Color(0xFFF0BD55);
  static const warningBorder = Color(0x80F0BD55);
  static const falling = Color(0xFFFF6868);
  static const rising = Color(0xFF43D9CC);
  static const stable = Color(0xFF49D697);
  static const waterBlue = Color(0xFF35A8D0);
}

Color _waterTrendColor(BuildContext context, WaterTrend? trend) =>
    switch (trend) {
      WaterTrend.rising => _BentoColors.rising,
      WaterTrend.stable => _BentoColors.stable,
      WaterTrend.falling => _BentoColors.falling,
      null => FluviAIThemeColors.of(context).textSecondary,
    };

String _waterVerdict(WaterTrend? trend, {required bool isRomanian}) =>
    switch (trend) {
      WaterTrend.rising => isRomanian ? 'În creștere' : 'Rising',
      WaterTrend.stable => isRomanian ? 'Stabil' : 'Stable',
      WaterTrend.falling => isRomanian ? 'În scădere' : 'Falling',
      null => isRomanian ? 'Trend indisponibil' : 'Trend unavailable',
    };

String _scoreVerdict(FishingScoreRating? rating, {required bool isRomanian}) =>
    switch (rating) {
      FishingScoreRating.excellent => isRomanian ? 'Excelent' : 'Excellent',
      FishingScoreRating.good => isRomanian ? 'Bun acum' : 'Good now',
      FishingScoreRating.fair => isRomanian ? 'Moderat' : 'Fair',
      FishingScoreRating.poor => isRomanian ? 'Slab' : 'Poor',
      null => isRomanian ? 'Date insuficiente' : 'Not enough data',
    };

Color _scoreColor(BuildContext context, FishingScoreRating? rating) =>
    switch (rating) {
      FishingScoreRating.excellent ||
      FishingScoreRating.good => _BentoColors.stable,
      FishingScoreRating.fair => _BentoColors.warning,
      FishingScoreRating.poor => _BentoColors.falling,
      null => FluviAIThemeColors.of(context).textMuted,
    };

String _formatNumber(double value) {
  if (value.roundToDouble() == value) return value.round().toString();
  return value.toStringAsFixed(1);
}

String _signedNumber(double value) {
  final text = _formatNumber(value.abs());
  if (value > 0) return '+$text';
  if (value < 0) return '−$text';
  return text;
}

String _homeSourceLabel(String source) {
  final trimmed = source.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{2,8}$').hasMatch(trimmed)) {
    return trimmed.toUpperCase();
  }
  return trimmed;
}

String _homeFreshnessAge(Duration age, {required bool isRomanian}) {
  final safe = age.isNegative ? Duration.zero : age;
  if (safe.inDays > 0) {
    if (isRomanian) {
      final days = safe.inDays;
      return 'acum $days ${days == 1 ? 'zi' : 'zile'}';
    }
    final days = safe.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }
  if (safe.inHours > 0) {
    return isRomanian ? 'acum ${safe.inHours} h' : '${safe.inHours} h ago';
  }
  if (safe.inMinutes > 0) {
    return isRomanian
        ? 'acum ${safe.inMinutes} min'
        : '${safe.inMinutes} min ago';
  }
  return isRomanian ? 'acum' : 'now';
}

String _localizedWindDirection(String direction, {required bool isRomanian}) {
  if (!isRomanian) return direction;
  return direction.replaceAll('W', 'V');
}

String _relativeAge(Duration age, {required bool isRomanian}) {
  final safe = age.isNegative ? Duration.zero : age;
  if (safe.inDays > 0) {
    return '${safe.inDays} ${isRomanian ? 'z' : 'd'}';
  }
  if (safe.inHours > 0) {
    return '${safe.inHours}h';
  }
  if (safe.inMinutes > 0) {
    return isRomanian
        ? 'acum ${safe.inMinutes} min'
        : '${safe.inMinutes} min ago';
  }
  return isRomanian ? 'acum' : 'now';
}

double? _distanceKm(
  double latitude,
  double longitude,
  double? otherLatitude,
  double? otherLongitude,
) {
  if (otherLatitude == null || otherLongitude == null) return null;
  const earthRadiusKm = 6371.0;
  double radians(double value) => value * math.pi / 180;
  final dLat = radians(otherLatitude - latitude);
  final dLon = radians(otherLongitude - longitude);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(radians(latitude)) *
          math.cos(radians(otherLatitude)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

const double homeLocalContentRadiusKm = 100;

List<CommunityPost> filterLocalHomePosts(
  Iterable<CommunityPost> posts, {
  required double? latitude,
  required double? longitude,
  double radiusKm = homeLocalContentRadiusKm,
}) {
  if (latitude == null || longitude == null) return const <CommunityPost>[];
  return List<CommunityPost>.unmodifiable(
    posts.where((post) {
      final distance = _distanceKm(
        latitude,
        longitude,
        post.latitude,
        post.longitude,
      );
      return distance != null && distance <= radiusKm;
    }),
  );
}

CommunityPost? selectLocalHomeReport(
  Iterable<CommunityPost> posts, {
  required double latitude,
  required double longitude,
  double radiusKm = homeLocalContentRadiusKm,
}) {
  final active =
      filterLocalHomePosts(
          posts,
          latitude: latitude,
          longitude: longitude,
          radiusKm: radiusKm,
        ).where((post) => post.isActiveReport).toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return active.firstOrNull;
}
