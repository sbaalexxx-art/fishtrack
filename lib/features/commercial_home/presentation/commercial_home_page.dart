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
import '../../../core/water/water_history_analysis.dart';
import '../../../models/station.dart';
import '../../../models/water_level.dart';
import '../../../models/weather.dart';
import '../../../services/community_service.dart';
import '../../../services/fishing_score_service.dart';
import '../../../services/location_service.dart';
import '../../../services/water_service.dart';
import '../../../services/weather_service.dart';
import '../../../widgets/weather/weather_visuals.dart';
import '../../../widgets/home_premium/side_menu.dart';
import '../../../widgets/home_premium/water_level_card.dart';
import '../../../screens/developer_mode_page.dart';
import '../../../services/build_mode_service.dart';
import '../../../services/diagnostics_service.dart';
import '../data/commercial_home_data_source.dart';

/// Production Home implementation of the approved continuous-canvas contract.
///
/// Presentation follows Figma node 24:30. Runtime data remains sourced from
/// the existing Water, Weather, FluviScore and Community services. The drawer
/// and every destination stay wired through the existing navigation contracts.
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

  /// Retained for shell/test compatibility. The final Home has no mini-map.
  final Widget? mapOverride;
  final FluviAccessTier accessTier;

  @override
  ConsumerState<CommercialHomePage> createState() => _CommercialHomePageState();
}

class _CommercialHomePageState extends ConsumerState<CommercialHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
    final notifier = ref.read(selectedContextProvider.notifier);
    if (station == null) {
      notifier.clearAutomaticStation();
      return;
    }
    notifier.publishAutomaticStation(station);
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

  void _openCatch(CommunityPost? catchPost) {
    if (catchPost == null) {
      _openDestination(AppDestination.catches);
      return;
    }
    _openDestination(AppDestination.catchDetail, arguments: catchPost);
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
              accessTier: widget.accessTier,
              onRefresh: () => _reload(forceRefresh: true),
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
              onNotifications: () =>
                  _openDestination(AppDestination.notifications),
              onDeveloperMode: BuildModeService.isDeveloperVisible
                  ? _openDeveloperMode
                  : null,
              onOpenWater: () => _openWater(snapshot),
              onOpenWaterSection: (section) => _openDestination(
                AppDestination.water,
                arguments: WaterHubRequest(
                  initialStation: snapshot?.station,
                  initialSection: section,
                ),
              ),
              onOpenWeather: () => _openDestination(
                AppDestination.weather,
                arguments: snapshot?.weather,
              ),
              onOpenScore: () => _openDestination(AppDestination.fluvi),
              onAskFluvi: () => _openDestination(
                AppDestination.askFluvi,
                arguments: ref.read(canonicalFluviContextProvider),
              ),
              onOpenCommunity: () => _openDestination(AppDestination.community),
              onOpenCatch: _openCatch,
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
    required this.accessTier,
    required this.onRefresh,
    required this.onMenu,
    required this.onNotifications,
    required this.onDeveloperMode,
    required this.onOpenWater,
    required this.onOpenWaterSection,
    required this.onOpenWeather,
    required this.onOpenScore,
    required this.onAskFluvi,
    required this.onOpenCommunity,
    required this.onOpenCatch,
    required this.onOpenReport,
  });

  final SelectedContext? selected;
  final CurrentDeviceLocation? currentLocation;
  final CommercialHomeSnapshot? snapshot;
  final bool loading;
  final bool isRomanian;
  final FluviAccessTier accessTier;
  final Future<void> Function() onRefresh;
  final VoidCallback onMenu;
  final VoidCallback onNotifications;
  final VoidCallback? onDeveloperMode;
  final VoidCallback onOpenWater;
  final ValueChanged<WaterHubSection> onOpenWaterSection;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenScore;
  final VoidCallback onAskFluvi;
  final VoidCallback onOpenCommunity;
  final ValueChanged<CommunityPost?> onOpenCatch;
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

    if (currentLocation?.hasValidCoordinates == true) {
      return copy(ro: 'Locație GPS', en: 'GPS location');
    }

    return copy(ro: 'Zona ta', en: 'Your area');
  }

  List<CommunityPost> get activeReports {
    final location = currentLocation;
    if (location == null) return const <CommunityPost>[];
    final reports =
        filterLocalHomePosts(
            snapshot?.communityPosts ?? const <CommunityPost>[],
            latitude: location.latitude,
            longitude: location.longitude,
          ).where((post) => post.isActiveReport).toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports.take(2).toList(growable: false);
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
          final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final adaptiveTextScale = textScale.clamp(1.0, 2.0).toDouble();
          final scaleDelta = adaptiveTextScale - 1;
          final headerHeight = 48 + scaleDelta * 20;
          final scoreHeight = 80 + scaleDelta * 90;
          final waterRowHeight = 300 + scaleDelta * 320;
          final capturesHeight = 220 + scaleDelta * 160;
          final askFluviHeight = 56 + scaleDelta * 44;
          final visibleReports = activeReports;

          return RefreshIndicator.adaptive(
            onRefresh: onRefresh,
            color: FluviAICommercialTokens.brandFocus,
            backgroundColor: FluviAIThemeColors.of(context).surface,
            child: SingleChildScrollView(
              key: const PageStorageKey<String>('canonical-home-scroll'),
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                FluviAICommercialTokens.bottomNavigationVisualHeight +
                    MediaQuery.viewPaddingOf(context).bottom +
                    16,
              ),
              child: Center(
                child: SizedBox(
                  key: const ValueKey<String>('home-continuous-canvas'),
                  width: contentWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BentoHeader(
                        height: headerHeight,
                        placeLabel: placeLabel,
                        isRomanian: isRomanian,
                        onMenu: onMenu,
                        onNotifications: onNotifications,
                        onDeveloperMode: onDeveloperMode,
                      ),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: FluviAIThemeColors.of(context).borderSoft,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: scoreHeight,
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
                      const SizedBox(height: 8),
                      _BentoWeatherCard(
                        weather: snapshot?.weather,
                        loading:
                            snapshot?.weatherStatus ==
                                CommercialHomeDomainStatus.loading ||
                            (snapshot == null && loading),
                        isRomanian: isRomanian,
                        onTap: onOpenWeather,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: waterRowHeight,
                        child: _BentoWaterCard(
                          snapshot: snapshot,
                          selectedContext: selected,
                          waterLabel: waterLabel,
                          loading:
                              snapshot?.waterStatus ==
                                  CommercialHomeDomainStatus.loading ||
                              (snapshot == null && loading),
                          isRomanian: isRomanian,
                          accessTier: accessTier,
                          onTap: onOpenWater,
                          onSelectSection: onOpenWaterSection,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: capturesHeight,
                        child: _BentoCommunityCard(
                          posts: filterLocalHomePosts(
                            snapshot?.communityPosts ?? const <CommunityPost>[],
                            latitude: currentLocation?.latitude,
                            longitude: currentLocation?.longitude,
                          ),
                          loading:
                              snapshot?.communityStatus ==
                                  CommercialHomeDomainStatus.loading ||
                              (snapshot == null && loading),
                          isRomanian: isRomanian,
                          onTap: onOpenCommunity,
                          onOpenCatch: onOpenCatch,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _BentoReportCard(
                        reports: visibleReports,
                        currentLocation: currentLocation,
                        loading:
                            snapshot?.communityStatus ==
                                CommercialHomeDomainStatus.loading ||
                            (snapshot == null && loading),
                        isRomanian: isRomanian,
                        onOpenReport: onOpenReport,
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: askFluviHeight,
                        child: _HomeAskFluviEntry(
                          isRomanian: isRomanian,
                          onTap: onAskFluvi,
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
  final label = location?.label?.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (label != null && label.isNotEmpty) return label;
  final locality = location?.locality?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return locality == null || locality.isEmpty ? null : locality;
}

class _BentoHeader extends StatelessWidget {
  const _BentoHeader({
    required this.height,
    required this.placeLabel,
    required this.isRomanian,
    required this.onMenu,
    required this.onNotifications,
    required this.onDeveloperMode,
  });

  final double height;
  final String placeLabel;
  final bool isRomanian;
  final VoidCallback onMenu;
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
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: const ValueKey<String>('home-menu-button'),
              tooltip: isRomanian ? 'Meniu' : 'Menu',
              onPressed: onMenu,
              icon: Icon(
                Icons.menu_rounded,
                size: 22,
                color: colors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: isRomanian
                  ? 'Locația fizică actuală'
                  : 'Current physical location',
              button: onDeveloperMode != null,
              child: Align(
                alignment: Alignment.center,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey<String>(
                      'commercial-home-context-header',
                    ),
                    onLongPress: onDeveloperMode,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 18,
                            color: FluviAICommercialTokens.brandFocus,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              placeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily:
                                    FluviAICommercialTokens.primaryFontFamily,
                                color: colors.textPrimary,
                                fontSize: 13,
                                height: 18 / 13,
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
          Semantics(
            label: isRomanian ? 'Notificări' : 'Notifications',
            button: true,
            child: SizedBox(
              key: const ValueKey<String>('canonical-home-alerts'),
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: isRomanian ? 'Notificări' : 'Notifications',
                onPressed: onNotifications,
                icon: Icon(
                  Icons.notifications_none_rounded,
                  size: 22,
                  color: colors.textPrimary,
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
    required this.selectedContext,
    required this.waterLabel,
    required this.loading,
    required this.isRomanian,
    required this.accessTier,
    required this.onTap,
    required this.onSelectSection,
  });

  final CommercialHomeSnapshot? snapshot;
  final SelectedContext? selectedContext;
  final String waterLabel;
  final bool loading;
  final bool isRomanian;
  final FluviAccessTier accessTier;
  final VoidCallback onTap;
  final ValueChanged<WaterHubSection> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final water = snapshot?.water;
    final reading = water?.latestReading;
    final trend = resolvedHomeWaterTrend(water);
    final delta = water?.deltaCm;
    final trendColor = _waterTrendColor(context, trend);
    final value = reading == null
        ? '—'
        : '${_formatNumber(reading.value)} ${reading.unit}';
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
    final status = _homeWaterStatusLabel(
      water,
      reading != null,
      isRomanian: isRomanian,
    );
    final waterContextLabel = snapshot?.station?.river.trim();
    final freshnessParts = <String>[
      if (waterContextLabel != null && waterContextLabel.isNotEmpty)
        waterContextLabel,
      source,
      status,
      if (age != null)
        '${isRomanian ? 'actualizat' : 'updated'} ${_homeFreshnessAge(age, isRomanian: isRomanian)}',
    ];
    final freshness = freshnessParts.join(' · ');
    final period = accessTier == FluviAccessTier.premium
        ? const Duration(days: 10)
        : const Duration(days: 3);
    final history = realWaterHistorySeries(
      water?.history ?? const <WaterLevel>[],
      period: period,
      stationId: snapshot?.station?.id,
    );
    final activeSection = _activeWaterSection(snapshot, selectedContext);
    final colors = FluviAIThemeColors.of(context);
    final accessible = MediaQuery.textScalerOf(context).scale(10) > 11.5;
    final deltaLabel = dailyDelta == null
        ? semantic.primary
        : '${_signedNumber(dailyDelta)} cm / 24h';
    final verdict = dailyDelta == null
        ? semantic.secondary
        : _waterVerdict(trend, isRomanian: isRomanian);

    return Column(
      key: const ValueKey('commercial-water-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isRomanian ? 'Nivelul apei' : 'Water level',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FluviAICommercialTokens.primaryFontFamily,
                  color: colors.textPrimary,
                  fontSize: 15,
                  height: 18 / 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('home-water-details'),
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: _BentoColors.waterBlue,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isRomanian ? 'Detalii' : 'Details'),
            ),
          ],
        ),
        Container(
          key: const ValueKey('home-water-selector'),
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: .34),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderSoft),
          ),
          child: Row(
            children: [
              _HomeWaterSegment(
                key: const ValueKey('home-water-section-danube'),
                label: isRomanian ? 'Dunăre' : 'Danube',
                selected: activeSection == WaterHubSection.danube,
                onTap: () => onSelectSection(WaterHubSection.danube),
              ),
              _HomeWaterSegmentDivider(color: colors.borderSoft),
              _HomeWaterSegment(
                key: const ValueKey('home-water-section-dams'),
                label: isRomanian ? 'Baraje' : 'Dams',
                selected: activeSection == WaterHubSection.dams,
                onTap: () => onSelectSection(WaterHubSection.dams),
              ),
              _HomeWaterSegmentDivider(color: colors.borderSoft),
              _HomeWaterSegment(
                key: const ValueKey('home-water-section-rivers'),
                label: isRomanian ? 'Râuri' : 'Rivers',
                selected: activeSection == WaterHubSection.rivers,
                onTap: () => onSelectSection(WaterHubSection.rivers),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Expanded(
          child: loading
              ? const _BentoSkeleton(lines: [128, 92, 170, 230])
              : Padding(
                  key: const ValueKey('home-water-cardless-content'),
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.water_drop_outlined,
                            size: 16,
                            color: _BentoColors.waterBlue,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              waterLabel,
                              key: const ValueKey('home-water-station-name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily:
                                    FluviAICommercialTokens.primaryFontFamily,
                                color: colors.textPrimary,
                                fontSize: 14,
                                height: 17 / 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: accessible ? 110 : 60,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: accessible ? 38 : 29,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  deltaLabel,
                                  key: const ValueKey('home-water-delta-24h'),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: FluviAICommercialTokens
                                        .primaryFontFamily,
                                    color: trendColor,
                                    fontSize: 25,
                                    height: 29 / 25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            if (accessible) ...[
                              if (verdict != null)
                                Text(
                                  verdict,
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontFamily: FluviAICommercialTokens
                                        .primaryFontFamily,
                                    color: trendColor,
                                    fontSize: 10.5,
                                    height: 13 / 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    isRomanian ? 'Nivel curent' : 'Current',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 10.5,
                                      height: 13 / 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      value,
                                      key: const ValueKey(
                                        'home-water-current-level',
                                      ),
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 14,
                                        height: 17 / 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              Row(
                                children: [
                                  if (verdict != null)
                                    Expanded(
                                      child: Text(
                                        verdict,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: FluviAICommercialTokens
                                              .primaryFontFamily,
                                          color: trendColor,
                                          fontSize: 10.5,
                                          height: 13 / 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  const SizedBox(width: 8),
                                  Text(
                                    isRomanian ? 'Nivel curent' : 'Current',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 10.5,
                                      height: 13 / 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    value,
                                    key: const ValueKey(
                                      'home-water-current-level',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 14,
                                      height: 17 / 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        child: history.length >= 2
                            ? Stack(
                                children: [
                                  Positioned.fill(
                                    child: HomeWaterHistoryLineChart(
                                      key: const ValueKey(
                                        'home-water-history-chart',
                                      ),
                                      readings: history,
                                      color: trendColor,
                                      unit: unit,
                                      localeCode: isRomanian ? 'ro' : 'en',
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Text(
                                      formatHomeWaterHistoryWindowLabel(
                                        history,
                                        isRo: isRomanian,
                                      ),
                                      key: const ValueKey(
                                        'home-water-history-window',
                                      ),
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 9.5,
                                        height: 11 / 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Center(
                                child: Text(
                                  isRomanian
                                      ? 'Istoric insuficient'
                                      : 'Insufficient history',
                                  key: const ValueKey(
                                    'home-water-history-unavailable',
                                  ),
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        key: const ValueKey('home-water-status'),
                        label: status,
                        child: Text(
                          freshness,
                          key: const ValueKey('home-water-provenance'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily:
                                FluviAICommercialTokens.primaryFontFamily,
                            color: colors.textSecondary,
                            fontSize: 10.5,
                            height: 13 / 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _HomeWaterSegment extends StatelessWidget {
  const _HomeWaterSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            color: selected
                ? _BentoColors.waterBlue.withValues(alpha: .12)
                : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? _BentoColors.waterBlue
                        : colors.textSecondary,
                    fontSize: 10.5,
                    height: 13 / 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeWaterSegmentDivider extends StatelessWidget {
  const _HomeWaterSegmentDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 1,
      height: 20,
      child: ColoredBox(color: color.withValues(alpha: .72)),
    ),
  );
}

List<WeatherForecastHour> selectUpcomingHomeWeatherHours(
  Iterable<WeatherForecastHour> hours, {
  DateTime? now,
  int limit = 4,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(const Duration(minutes: 30));
  final ordered = hours.where((hour) => !hour.time.isBefore(cutoff)).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  return List<WeatherForecastHour>.unmodifiable(ordered.take(limit));
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
    final colors = FluviAIThemeColors.of(context);
    final brightness = Theme.of(context).brightness;
    final kind = weatherVisualKind(data?.condition ?? '');
    final daylight = data == null ? true : weatherIsDaylight(data);
    final accent = data == null
        ? colors.textSecondary
        : weatherVisualAccent(
            kind,
            isDaylight: daylight,
            brightness: brightness,
          );
    final atmosphere = homeWeatherAtmosphereGradient(
      kind,
      isDaylight: daylight,
      brightness: brightness,
    );
    final status = _weatherStatusLabel(weather, isRomanian: isRomanian);
    final hourly = data == null
        ? const <WeatherForecastHour>[]
        : selectUpcomingHomeWeatherHours(data.hourlyForecast);
    final accessible = MediaQuery.textScalerOf(context).scale(10) > 12.5;

    return Column(
      key: const ValueKey('commercial-weather-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isRomanian ? 'Vreme acum' : 'Weather now',
                style: TextStyle(
                  fontFamily: FluviAICommercialTokens.primaryFontFamily,
                  color: colors.textPrimary,
                  fontSize: 15,
                  height: 18 / 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              status,
              key: const ValueKey('home-weather-status'),
              style: TextStyle(
                fontFamily: FluviAICommercialTokens.primaryFontFamily,
                color: weather?.isStale == true
                    ? _BentoColors.warning
                    : data == null
                    ? colors.textSecondary
                    : _BentoColors.stable,
                fontSize: 10,
                height: 12 / 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 7),
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('home-weather-open'),
            onTap: onTap,
            borderRadius: BorderRadius.zero,
            child: loading
                ? const SizedBox(
                    height: 122,
                    child: _BentoSkeleton(lines: [90, 160, 210]),
                  )
                : data == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      isRomanian
                          ? 'Vremea este momentan indisponibilă'
                          : 'Weather is currently unavailable',
                      key: const ValueKey('home-weather-unavailable'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : DecoratedBox(
                    key: const ValueKey('home-living-weather-atmosphere'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: atmosphere,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: WeatherAtmosphereBackdrop(
                            kind: kind,
                            isDaylight: daylight,
                            foreground: accent,
                            compact: true,
                            intensity: .52,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${data.temperature.round()}°',
                                    key: const ValueKey(
                                      'home-weather-temperature',
                                    ),
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 30,
                                      height: 33 / 30,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      weatherConditionLabel(
                                        data.condition,
                                        isRomanian: isRomanian,
                                      ),
                                      key: const ValueKey(
                                        'home-weather-condition',
                                      ),
                                      maxLines: accessible ? 3 : 2,
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 12.5,
                                        height: 16 / 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    weatherVisualIcon(
                                      kind,
                                      isDaylight: daylight,
                                    ),
                                    key: const ValueKey(
                                      'home-weather-condition-icon',
                                    ),
                                    size: accessible ? 24 : 20,
                                    color: accent.withValues(alpha: .84),
                                  ),
                                ],
                              ),
                              Divider(height: 8, color: colors.borderSoft),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final metricWidth = accessible
                                      ? (constraints.maxWidth - 10) / 2
                                      : (constraints.maxWidth - 20) / 3;
                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      SizedBox(
                                        width: metricWidth,
                                        child: _HomeWeatherMetric(
                                          icon: Icons.air_rounded,
                                          label: isRomanian ? 'Vânt' : 'Wind',
                                          value:
                                              '${data.windSpeed.round()} km/h · ${_localizedWindDirection(data.windDirectionLabel, isRomanian: isRomanian)}',
                                          secondaryValue:
                                              data.windGusts.isFinite &&
                                                  data.windGusts > 0
                                              ? '${isRomanian ? 'Rafale' : 'Gusts'} ${data.windGusts.round()} km/h'
                                              : null,
                                          valueKey: const ValueKey(
                                            'home-weather-wind',
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: metricWidth,
                                        child: _HomeWeatherMetric(
                                          icon: Icons.speed_rounded,
                                          label: isRomanian
                                              ? 'Presiune'
                                              : 'Pressure',
                                          value: data.pressure == null
                                              ? '—'
                                              : '${data.pressure!.round()} hPa',
                                          valueKey: const ValueKey(
                                            'home-weather-pressure',
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: metricWidth,
                                        child: _HomeWeatherMetric(
                                          icon: Icons.water_drop_outlined,
                                          label: isRomanian ? 'Ploaie' : 'Rain',
                                          value:
                                              '${data.precipitationProbability.round()}%',
                                          valueKey: const ValueKey(
                                            'home-weather-precipitation',
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              if (hourly.isNotEmpty) ...[
                                Divider(height: 8, color: colors.borderSoft),
                                SizedBox(
                                  key: const ValueKey(
                                    'home-weather-hourly-strip',
                                  ),
                                  height: accessible ? 104 : 42,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    physics: const ClampingScrollPhysics(),
                                    itemCount: hourly.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 4),
                                    itemBuilder: (context, index) => SizedBox(
                                      width: accessible ? 92 : 68,
                                      child: _HomeWeatherHour(
                                        hour: hourly[index],
                                        fallbackDaylight: daylight,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _HomeWeatherMetric extends StatelessWidget {
  const _HomeWeatherMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.valueKey,
    this.secondaryValue,
  });

  final IconData icon;
  final String value;
  final String label;
  final Key valueKey;
  final String? secondaryValue;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 10.5,
            height: 13 / 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, size: 15, color: colors.textSecondary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                value,
                key: valueKey,
                maxLines: 2,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12.5,
                  height: 16 / 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (secondaryValue != null)
          Text(
            secondaryValue!,
            key: const ValueKey('home-weather-gusts'),
            maxLines: 1,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
              height: 12 / 10,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _HomeWeatherHour extends StatelessWidget {
  const _HomeWeatherHour({required this.hour, required this.fallbackDaylight});

  final WeatherForecastHour hour;
  final bool fallbackDaylight;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final kind = weatherVisualKind(hour.condition ?? '');
    final daylight = hour.isDay ?? fallbackDaylight;
    final accent = weatherVisualAccent(
      kind,
      isDaylight: daylight,
      brightness: Theme.of(context).brightness,
    );
    final local = hour.time.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 9.5,
            height: 11 / 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Icon(
              weatherVisualIcon(kind, isDaylight: daylight),
              size: 15,
              color: accent,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${hour.temperature.round()}°',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    height: 15 / 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${hour.precipitationProbability.round()}%',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 9.5,
            height: 11 / 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    final colors = FluviAIThemeColors.of(context);
    final accent = _scoreColor(context, score?.rating);
    final progress = value == null
        ? 0.0
        : (value / 100).clamp(0.0, 1.0).toDouble();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      key: const ValueKey('commercial-score-card'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: loading
            ? const _BentoSkeleton(lines: [48, 116])
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.square(
                            key: const ValueKey<String>('home-fluviscore-ring'),
                            dimension: 52,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey<String>(
                                'home-fluviscore-progress-${value?.round() ?? -1}',
                              ),
                              tween: Tween<double>(begin: 0, end: progress),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 700),
                              curve: reduceMotion
                                  ? Curves.linear
                                  : Curves.easeOutCubic,
                              builder: (context, animatedProgress, _) =>
                                  CircularProgressIndicator(
                                    value: animatedProgress,
                                    strokeWidth: 4,
                                    strokeCap: StrokeCap.round,
                                    backgroundColor: accent.withValues(
                                      alpha: .14,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      accent,
                                    ),
                                  ),
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    value == null
                                        ? '—'
                                        : value.round().toString(),
                                    key: const ValueKey<String>(
                                      'home-fluviscore-value',
                                    ),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontFamily: FluviAICommercialTokens
                                          .primaryFontFamily,
                                      color: colors.textPrimary,
                                      fontSize: 16,
                                      height: 17 / 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (value != null)
                                    Text(
                                      '/ 100',
                                      key: const ValueKey<String>(
                                        'home-fluviscore-scale',
                                      ),
                                      style: TextStyle(
                                        fontFamily: FluviAICommercialTokens
                                            .primaryFontFamily,
                                        color: colors.textSecondary,
                                        fontSize: 8,
                                        height: 9 / 8,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FluviScore',
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily:
                                  FluviAICommercialTokens.primaryFontFamily,
                              color: colors.textSecondary,
                              fontSize: 10.5,
                              height: 13 / 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _scoreVerdict(
                              score?.rating,
                              isRomanian: isRomanian,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily:
                                  FluviAICommercialTokens.primaryFontFamily,
                              color: accent,
                              fontSize: 13,
                              height: 16 / 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (score != null && score!.confidence > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              isRomanian
                                  ? 'Încredere: ${score!.confidence}%'
                                  : 'Confidence: ${score!.confidence}%',
                              key: const ValueKey<String>(
                                'home-fluviscore-confidence',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily:
                                    FluviAICommercialTokens.primaryFontFamily,
                                color: colors.textSecondary,
                                fontSize: 10.5,
                                height: 13 / 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: _BentoColors.accent,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

List<CommunityPost> selectDistinctHomeCatches(
  Iterable<CommunityPost> posts, {
  int limit = 6,
}) {
  final sorted =
      posts
          .where(
            // Canonical moderation only; never fish-presence, species, or
            // photo-quality inference.
            (post) =>
                post.type == CommunityPostType.catchPost && !post.isSuspicious,
          )
          .toList(growable: false)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final ids = <String>{};
  final imageUrls = <String>{};
  final selected = <CommunityPost>[];
  for (final post in sorted) {
    if (!ids.add(post.id)) continue;
    final imageUrl = _safePublicImageUrl(post.imageUrl);
    if (imageUrl != null && !imageUrls.add(imageUrl)) continue;
    selected.add(post);
    if (selected.length == limit) break;
  }
  return List<CommunityPost>.unmodifiable(selected);
}

String? _safePublicImageUrl(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
    return null;
  }
  return value;
}

class _BentoCommunityCard extends StatelessWidget {
  const _BentoCommunityCard({
    required this.posts,
    required this.loading,
    required this.isRomanian,
    required this.onTap,
    required this.onOpenCatch,
  });

  final List<CommunityPost> posts;
  final bool loading;
  final bool isRomanian;
  final VoidCallback onTap;
  final ValueChanged<CommunityPost?> onOpenCatch;

  @override
  Widget build(BuildContext context) {
    final catches = selectDistinctHomeCatches(posts);
    final colors = FluviAIThemeColors.of(context);

    return Column(
      key: const ValueKey('commercial-community-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isRomanian ? 'Capturi recente' : 'Recent catches',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FluviAICommercialTokens.primaryFontFamily,
                  color: colors.textPrimary,
                  fontSize: 15,
                  height: 18 / 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('home-catches-see-all'),
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: _BentoColors.accent,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isRomanian ? 'Vezi toate' : 'See all'),
            ),
          ],
        ),
        Expanded(
          child: loading
              ? const _BentoSkeleton(lines: [92, 92, 92])
              : catches.isEmpty
              ? Center(
                  child: Text(
                    isRomanian
                        ? 'Nicio captură publică în această zonă'
                        : 'No public catches in this area',
                    key: const ValueKey('home-catches-empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final visibleItems = constraints.maxWidth >= 340
                        ? 2.22
                        : 2.08;
                    final itemWidth =
                        ((constraints.maxWidth - 10) / visibleItems)
                            .clamp(132.0, 165.0)
                            .toDouble();
                    return ListView.separated(
                      key: const ValueKey('home-catches-strip'),
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.only(right: 24),
                      itemCount: catches.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final item = catches[index];
                        return SizedBox(
                          key: ValueKey<String>('home-catch-slot-$index'),
                          width: itemWidth,
                          child: _HomeCatchTile(
                            post: item,
                            isRomanian: isRomanian,
                            onTap: () => onOpenCatch(item),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HomeCatchTile extends StatelessWidget {
  const _HomeCatchTile({
    required this.post,
    required this.isRomanian,
    required this.onTap,
  });

  final CommunityPost post;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final imageUrl = _safePublicImageUrl(post.imageUrl);
    final age = DateTime.now().difference(post.createdAt).abs();
    final measurements = <String>[
      if (post.weight != null && post.weight!.isFinite)
        '${_formatNumber(post.weight!)} kg',
      if (post.length != null && post.length!.isFinite)
        '${_formatNumber(post.length!)} cm',
    ];
    final title = post.title.trim().isEmpty
        ? (isRomanian ? 'Captură' : 'Catch')
        : post.title.trim();

    return Semantics(
      button: true,
      label: title,
      value: measurements.join(' · '),
      child: Material(
        key: ValueKey<String>('home-catch-${post.id}'),
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null)
                Image.network(
                  imageUrl,
                  key: ValueKey<String>('home-catch-image-${post.id}'),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, _, _) =>
                      _CatchImageFallback(colors: colors),
                )
              else
                _CatchImageFallback(colors: colors),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [.38, 1],
                      colors: [Colors.transparent, Color(0xD900080D)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 7,
                right: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.withValues(alpha: .82),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    child: Text(
                      _relativeAge(age, isRomanian: isRomanian),
                      style: TextStyle(
                        fontFamily: FluviAICommercialTokens.primaryFontFamily,
                        color: colors.textPrimary,
                        fontSize: 10,
                        height: 12 / 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: ValueKey<String>('home-catch-title-${post.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: FluviAICommercialTokens.primaryFontFamily,
                        color: Colors.white,
                        fontSize: 14,
                        height: 17 / 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      measurements.isEmpty
                          ? (isRomanian ? 'Detalii publice' : 'Public details')
                          : measurements.join(' · '),
                      key: ValueKey<String>('home-catch-metadata-${post.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: FluviAICommercialTokens.primaryFontFamily,
                        color: Color(0xFFE2EDF2),
                        fontSize: 11.5,
                        height: 14 / 11.5,
                        fontWeight: FontWeight.w500,
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

class _CatchImageFallback extends StatelessWidget {
  const _CatchImageFallback({required this.colors});

  final FluviAIThemeColors colors;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: colors.surfaceStrong,
    child: Icon(Icons.phishing_rounded, color: colors.textSecondary, size: 24),
  );
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
    required this.reports,
    required this.currentLocation,
    required this.loading,
    required this.isRomanian,
    required this.onOpenReport,
  });

  final List<CommunityPost> reports;
  final CurrentDeviceLocation? currentLocation;
  final bool loading;
  final bool isRomanian;
  final ValueChanged<CommunityPost?> onOpenReport;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Column(
      key: const ValueKey('commercial-reports-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isRomanian ? 'Rapoarte live' : 'Live reports',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FluviAICommercialTokens.primaryFontFamily,
                  color: colors.textPrimary,
                  fontSize: 15,
                  height: 18 / 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('home-reports-see-all'),
              onPressed: () => onOpenReport(null),
              style: TextButton.styleFrom(
                foregroundColor: _BentoColors.accent,
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isRomanian ? 'Vezi toate' : 'See all'),
            ),
          ],
        ),
        if (loading)
          const SizedBox(height: 48, child: _BentoSkeleton(lines: [160]))
        else if (reports.isEmpty)
          Material(
            key: const ValueKey('home-reports-empty-action'),
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onOpenReport(null),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Icon(
                      Icons.near_me_outlined,
                      size: 17,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        isRomanian
                            ? 'Niciun raport activ în apropiere'
                            : 'No active report nearby',
                        key: const ValueKey('home-reports-empty'),
                        maxLines: 2,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                          height: 15 / 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isRomanian ? 'Vezi rapoarte' : 'View reports',
                      style: const TextStyle(
                        color: _BentoColors.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 17,
                      color: _BentoColors.accent,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < reports.length; index++) ...[
                if (index > 0) Divider(height: 1, color: colors.borderSoft),
                SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(10) > 12.5
                      ? 72
                      : 50,
                  child: _HomeReportRow(
                    report: reports[index],
                    currentLocation: currentLocation,
                    isRomanian: isRomanian,
                    onTap: () => onOpenReport(reports[index]),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _HomeReportRow extends StatelessWidget {
  const _HomeReportRow({
    required this.report,
    required this.currentLocation,
    required this.isRomanian,
    required this.onTap,
  });

  final CommunityPost report;
  final CurrentDeviceLocation? currentLocation;
  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final category = report.reportCategory ?? ReportCategory.other;
    final accent = _homeReportColor(category);
    final distance = currentLocation == null
        ? null
        : _distanceKm(
            currentLocation!.latitude,
            currentLocation!.longitude,
            report.latitude,
            report.longitude,
          );
    final metadata = <String>[
      _relativeAge(
        DateTime.now().difference(report.createdAt).abs(),
        isRomanian: isRomanian,
      ),
      if (distance != null)
        '${distance.toStringAsFixed(1).replaceAll('.', ',')} km',
      '${report.stillValidCount} ${isRomanian ? 'confirmări' : 'confirmations'}',
    ].join(' · ');

    return Material(
      key: ValueKey<String>('home-report-${report.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_homeReportIcon(category), size: 17, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizedHomeReportCategory(
                      category,
                      isRomanian: isRomanian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      height: 16 / 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metadata,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 10.5,
                      height: 13 / 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _homeReportIcon(ReportCategory category) => switch (category) {
  ReportCategory.fishActivity ||
  ReportCategory.goodFishing ||
  ReportCategory.poorFishing => Icons.phishing_rounded,
  ReportCategory.strongCurrent ||
  ReportCategory.noCurrent ||
  ReportCategory.highWater ||
  ReportCategory.lowWater => Icons.waves_rounded,
  ReportCategory.accessBlocked => Icons.block_rounded,
  ReportCategory.boats => Icons.directions_boat_rounded,
  ReportCategory.parkingAvailable => Icons.local_parking_rounded,
  ReportCategory.waterClarity ||
  ReportCategory.floatingGrass => Icons.visibility_rounded,
  ReportCategory.poaching ||
  ReportCategory.theftWarning => Icons.warning_amber_rounded,
  ReportCategory.other => Icons.outlined_flag_rounded,
};

Color _homeReportColor(ReportCategory category) => switch (category) {
  ReportCategory.goodFishing ||
  ReportCategory.parkingAvailable => _BentoColors.stable,
  ReportCategory.strongCurrent ||
  ReportCategory.highWater ||
  ReportCategory.lowWater => _BentoColors.waterBlue,
  ReportCategory.poaching ||
  ReportCategory.theftWarning ||
  ReportCategory.accessBlocked => _BentoColors.warning,
  _ => _BentoColors.accent,
};

class _HomeAskFluviEntry extends StatelessWidget {
  const _HomeAskFluviEntry({required this.isRomanian, required this.onTap});

  final bool isRomanian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Material(
      key: const ValueKey('home-ask-fluvi'),
      color: Color.alphaBlend(
        _BentoColors.accent.withValues(alpha: .08),
        colors.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: _BentoColors.accent.withValues(alpha: .34)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 19,
                color: _BentoColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isRomanian
                      ? 'Întreabă Fluvi despre zona ta…'
                      : 'Ask Fluvi about your area…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12,
                    height: 15 / 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 19,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
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
  static const accent = FluviAICommercialTokens.accent;
  static const warning = FluviAICommercialTokens.warning;
  static const falling = FluviAICommercialTokens.waterFalling;
  static const rising = FluviAICommercialTokens.waterRising;
  static const stable = FluviAICommercialTokens.waterStable;
  static const waterBlue = FluviAICommercialTokens.brandFocus;
}

Color _waterTrendColor(BuildContext context, WaterTrend? trend) =>
    switch (trend) {
      WaterTrend.rising => _BentoColors.rising,
      WaterTrend.stable => _BentoColors.stable,
      WaterTrend.falling => _BentoColors.falling,
      null => FluviAIThemeColors.of(context).textSecondary,
    };

WaterHubSection? _activeWaterSection(
  CommercialHomeSnapshot? snapshot,
  SelectedContext? selected,
) {
  if (selected?.damId != null ||
      selected?.reservoirId != null ||
      selected?.hydropowerPlantId != null) {
    return WaterHubSection.dams;
  }
  final river = (snapshot?.station?.river ?? selected?.riverName ?? '')
      .toLowerCase();
  if (river.contains('dună') ||
      river.contains('duna') ||
      river.contains('danube')) {
    return WaterHubSection.danube;
  }
  if (river.isNotEmpty ||
      selected?.riverKey != null ||
      selected?.waterId != null) {
    return WaterHubSection.rivers;
  }
  return null;
}

String _homeWaterStatusLabel(
  WaterUiResult? water,
  bool hasReading, {
  required bool isRomanian,
}) {
  if (!hasReading || water == null) return 'UNKNOWN';
  if (water.isStale) return isRomanian ? 'VECHI' : 'STALE';
  return switch (water.status) {
    WaterUiStatus.availableHistory ||
    WaterUiStatus.insufficientHistory => 'LIVE',
    WaterUiStatus.providerError => 'CACHE',
    WaterUiStatus.unavailable => 'UNKNOWN',
  };
}

String _waterVerdict(WaterTrend? trend, {required bool isRomanian}) =>
    switch (trend) {
      WaterTrend.rising => isRomanian ? 'În creștere' : 'Rising',
      WaterTrend.stable => isRomanian ? 'Stabil' : 'Stable',
      WaterTrend.falling => isRomanian ? 'În scădere' : 'Falling',
      null => isRomanian ? 'Trend indisponibil' : 'Trend unavailable',
    };

String _scoreVerdict(FishingScoreRating? rating, {required bool isRomanian}) =>
    switch (rating) {
      FishingScoreRating.excellent =>
        isRomanian ? 'Condiții excelente' : 'Excellent conditions',
      FishingScoreRating.good =>
        isRomanian ? 'Condiții bune' : 'Good conditions',
      FishingScoreRating.fair => isRomanian ? 'Moderat' : 'Fair',
      FishingScoreRating.poor => isRomanian ? 'Slab' : 'Poor',
      null => isRomanian ? 'Date insuficiente' : 'Not enough data',
    };

String _weatherStatusLabel(
  WeatherHomeResult? weather, {
  required bool isRomanian,
}) {
  if (weather == null) return 'UNKNOWN';
  if (weather.isStale) return isRomanian ? 'VECHI' : 'STALE';
  return switch (weather.status) {
    WeatherHomeStatus.available => 'LIVE',
    WeatherHomeStatus.staleFallback => 'CACHE',
    WeatherHomeStatus.locationUnavailable ||
    WeatherHomeStatus.providerError ||
    WeatherHomeStatus.unavailable => 'UNKNOWN',
  };
}

Color _scoreColor(BuildContext context, FishingScoreRating? rating) =>
    switch (rating) {
      FishingScoreRating.excellent ||
      FishingScoreRating.good => FluviAICommercialTokens.fluviScoreActive,
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
