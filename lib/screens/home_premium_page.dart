import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../widgets/home_premium/dashboard.dart';
import '../widgets/home_premium/home_map.dart';
import '../widgets/home_premium/home_premium_layout.dart';
import '../widgets/home_premium/side_menu.dart';
import '../services/build_mode_service.dart';
import 'water_level_page.dart';
import 'weather_page.dart';
import 'developer_mode_page.dart';
import 'fishing_insights_page.dart';
import 'notifications_page.dart';

class HomePremiumPage extends StatefulWidget {
  const HomePremiumPage({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  State<HomePremiumPage> createState() => _HomePremiumPageState();
}

class _HomePremiumPageState extends State<HomePremiumPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _homeMapKey = GlobalKey(debugLabel: 'home-premium-map');
  final GlobalKey _dashboardKey = GlobalKey(debugLabel: 'home-dashboard');
  final HomePremiumMapController _homeMapController =
      HomePremiumMapController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _landscapeDashboardController = ScrollController();
  HomePremiumMap? _homeMap;
  HomeMapLocationAvailability _locationAvailability =
      HomeMapLocationAvailability.locating;
  String? _locationLabel;
  Orientation? _orientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _homeMap != null) return;
      final homeMap = HomePremiumMap(
        key: _homeMapKey,
        controller: _homeMapController,
        onTap: () => widget.onNavigate(1),
        onLocationAvailabilityChanged: _handleLocationAvailability,
        onLocationLabelChanged: _handleLocationLabel,
      );
      setState(() => _homeMap = homeMap);
    });
  }

  void _handleLocationAvailability(HomeMapLocationAvailability value) {
    if (!mounted || value == _locationAvailability) return;
    setState(() => _locationAvailability = value);
  }

  void _handleLocationLabel(String? value) {
    if (!mounted || value == _locationLabel) return;
    setState(() => _locationLabel = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    final previousOrientation = _orientation;
    _orientation = orientation;

    if (previousOrientation == null || previousOrientation == orientation) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _orientation != orientation) {
        return;
      }
      for (final controller in [
        _scrollController,
        _landscapeDashboardController,
      ]) {
        if (controller.hasClients) {
          controller.jumpTo(controller.position.minScrollExtent);
        }
      }
    });
  }

  @override
  void dispose() {
    _landscapeDashboardController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _buildMapOverlayAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double iconSize = 19,
    bool transparent = false,
  }) {
    final button = Semantics(
      button: true,
      label: label,
      child: Material(
        color: transparent
            ? Colors.transparent
            : const Color(0xFF08131C).withValues(alpha: .62),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: SizedBox.square(
            dimension: 48,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
    return Tooltip(message: label, child: button);
  }

  Widget _buildBrandMenuCluster() {
    final openDrawerLabel = MaterialLocalizations.of(
      context,
    ).openAppDrawerTooltip;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF08131C).withValues(alpha: .62),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .20),
            blurRadius: 14,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMapOverlayAction(
              icon: Icons.menu_rounded,
              label: openDrawerLabel,
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              transparent: true,
            ),
            Container(
              width: 1,
              height: 22,
              color: Colors.white.withValues(alpha: .10),
            ),
            Semantics(
              label: 'FluviAI',
              image: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: BuildModeService.isDeveloperVisible
                    ? () => _openPage(const DeveloperModePage())
                    : null,
                child: SizedBox(
                  width: 38,
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/branding/fluviai_logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationChip({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: const Color(0xFF08131C).withValues(alpha: .62),
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: _homeMapController.recenter,
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color == Colors.white54
                              ? Colors.white60
                              : Colors.white,
                          fontSize: 12,
                          height: 1,
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
    );
  }

  Widget _buildMapOverlay() {
    final (
      locationIcon,
      locationColor,
      locationText,
    ) = switch (_locationAvailability) {
      HomeMapLocationAvailability.locating => (
        Icons.location_searching_rounded,
        const Color(0xFF12D8D6),
        '${context.l10n.currentLocation}: ${context.l10n.loading}',
      ),
      HomeMapLocationAvailability.available => (
        Icons.location_on_rounded,
        const Color(0xFF12D8D6),
        _locationLabel ?? context.l10n.currentLocation,
      ),
      HomeMapLocationAvailability.unavailable => (
        Icons.location_off_rounded,
        Colors.white54,
        '${context.l10n.currentLocation}: ${context.l10n.notAvailable}',
      ),
    };

    return SizedBox(
      height: 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBrandMenuCluster(),
          const SizedBox(width: 6),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: _buildLocationChip(
                  icon: locationIcon,
                  color: locationColor,
                  label: locationText,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildMapOverlayAction(
            icon: Icons.notifications_none_rounded,
            label: context.l10n.notifications,
            onTap: () => _openPage(const NotificationsPage()),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(HomePremiumLayout layout) {
    return PremiumDashboard(
      key: _dashboardKey,
      layout: layout,
      onWaterLevelPressed: (station) =>
          _openPage(WaterLevelPage(initialStation: station)),
      onWeatherPressed: () => _openPage(const WeatherPage()),
      onWeatherMetricPressed: (section) =>
          _openPage(WeatherPage(initialSection: section)),
      onCommunityPressed: () => widget.onNavigate(2),
      onAiPressed: () => _openPage(const FishingInsightsPage()),
    );
  }

  Widget _buildHomeMapSlot() {
    final homeMap = _homeMap;
    if (homeMap != null) return homeMap;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF16212B)),
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF07131D).withValues(alpha: .72),
                  const Color(0xFF16212B),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapHero(
    HomePremiumLayout layout, {
    required EdgeInsets overlayInsets,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildHomeMapSlot()),
        Positioned(
          top: overlayInsets.top + (layout.isLandscape ? 2 : 6),
          left: overlayInsets.left + 8,
          right: overlayInsets.right + 8,
          child: _buildMapOverlay(),
        ),
      ],
    );
  }

  double _portraitHeroHeight(HomePremiumLayout layout) {
    if (!layout.isSmallPhone) return layout.heroMapHeight;
    return (layout.usableHeight * .40).clamp(220.0, 390.0).toDouble();
  }

  Widget _buildPortraitHome(
    HomePremiumLayout layout,
    BoxConstraints constraints,
    EdgeInsets viewPadding,
  ) {
    final mapDashboardSpacing = (layout.sectionGap * .75)
        .clamp(4.0, 6.0)
        .toDouble();

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _portraitHeroHeight(layout),
              child: _buildMapHero(layout, overlayInsets: viewPadding),
            ),
            SizedBox(height: mapDashboardSpacing),
            Padding(
              padding: EdgeInsets.only(
                left: layout.horizontalPadding + viewPadding.left,
                right: layout.horizontalPadding + viewPadding.right,
              ),
              child: _buildDashboard(layout),
            ),
            SizedBox(height: layout.bottomSafeClearance),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeHome(HomePremiumLayout layout, EdgeInsets viewPadding) {
    final dashboardTopInset = viewPadding.top + 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 58,
          child: MediaQuery.removeViewPadding(
            context: context,
            removeRight: true,
            child: _buildMapHero(
              layout,
              overlayInsets: EdgeInsets.only(
                top: viewPadding.top,
                left: viewPadding.left,
              ),
            ),
          ),
        ),
        SizedBox(width: layout.sectionGap),
        Expanded(
          flex: 42,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              layout.horizontalPadding,
              dashboardTopInset,
              layout.horizontalPadding + viewPadding.right,
              0,
            ),
            child: SingleChildScrollView(
              controller: _landscapeDashboardController,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.only(bottom: layout.sectionGap),
                child: _buildDashboard(layout),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFF0F1115),
        drawer: const HomeSideMenu(),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.maxWidth.isFinite ||
                !constraints.maxHeight.isFinite ||
                constraints.maxWidth <= 0 ||
                constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }

            final viewportSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            final viewPadding = MediaQuery.viewPaddingOf(context);
            final layout = HomePremiumLayout.fromViewport(
              context,
              viewportSize: viewportSize,
              systemSafeArea: viewPadding,
              bottomNavigationOverlaysBody: false,
            );
            return layout.isLandscape
                ? _buildLandscapeHome(layout, viewPadding)
                : _buildPortraitHome(layout, constraints, viewPadding);
          },
        ),
      ),
    );
  }
}
