import 'package:flutter/material.dart';

import '../widgets/home_premium/dashboard.dart';
import '../widgets/home_premium/home_header.dart';
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
  final ScrollController _scrollController = ScrollController();
  final ScrollController _landscapeDashboardController = ScrollController();
  late final HomePremiumMap _homeMap;
  HomeMapLocationAvailability _locationAvailability =
      HomeMapLocationAvailability.locating;
  String? _locationLabel;
  Orientation? _orientation;

  @override
  void initState() {
    super.initState();
    _homeMap = HomePremiumMap(
      key: _homeMapKey,
      onLocationAvailabilityChanged: _handleLocationAvailability,
      onLocationLabelChanged: _handleLocationLabel,
    );
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

  Widget _buildHeader(HomePremiumLayout layout) {
    final avatarSize = 26 * layout.iconScale;
    return SizedBox(
      height: layout.headerHeight * .70,
      child: Row(
        children: [
          Expanded(
            child: HomePremiumHeader(
              notificationCount: 0,
              onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
              onNotificationPressed: () => _openPage(const NotificationsPage()),
              onLogoLongPress: BuildModeService.isDeveloperVisible
                  ? () => _openPage(const DeveloperModePage())
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF12D8D6).withValues(alpha: 0.22),
                  const Color(0xFF132631).withValues(alpha: 0.94),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF12D8D6).withValues(alpha: 0.62),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF12D8D6).withValues(alpha: 0.12),
                  blurRadius: 12,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Icon(
              Icons.person_outline_rounded,
              color: const Color(0xFFEAFDFF),
              size: 15 * layout.iconScale,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationBridge(HomePremiumLayout layout) {
    final isRo = Localizations.localeOf(context).languageCode == 'ro';
    final (icon, color, label) = switch (_locationAvailability) {
      HomeMapLocationAvailability.locating => (
        Icons.location_searching_rounded,
        const Color(0xFF12D8D6),
        isRo
            ? 'Se determin\u0103 loca\u021bia\u2026'
            : 'Determining location\u2026',
      ),
      HomeMapLocationAvailability.available => (
        Icons.location_on_rounded,
        const Color(0xFF12D8D6),
        _locationLabel ??
            (isRo ? 'Loca\u021bia curent\u0103' : 'Current location'),
      ),
      HomeMapLocationAvailability.unavailable => (
        Icons.location_off_rounded,
        Colors.white54,
        isRo ? 'Loca\u021bie indisponibil\u0103' : 'Location unavailable',
      ),
    };
    return SizedBox(
      height: 18,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 4.0;
          final contentWidth = constraints.maxWidth - (horizontalPadding * 2);
          final minimumLineWidth = layout.isLandscapePhone ? 72.0 : 28.0;
          final iconWidth = 12 * layout.iconScale;
          final maximumTextWidth =
              contentWidth - (minimumLineWidth * 2) - iconWidth - 16;
          final preferredTextWidth =
              contentWidth * (layout.isLandscapePhone ? .52 : .58);
          final textMaxWidth = preferredTextWidth < maximumTextWidth
              ? preferredTextWidth
              : maximumTextWidth;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: const Color(0xFF12D8D6).withValues(alpha: .58),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(icon, size: iconWidth, color: color),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: textMaxWidth.clamp(48.0, contentWidth).toDouble(),
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          _locationAvailability ==
                              HomeMapLocationAvailability.unavailable
                          ? Colors.white54
                          : const Color(0xFFF4FBFD),
                      fontSize: 9.5 * layout.bodyFontScale,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .08,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 1,
                    color: const Color(0xFF12D8D6).withValues(alpha: .58),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboard(HomePremiumLayout layout) {
    return PremiumDashboard(
      layout: layout,
      onWaterLevelPressed: () => _openPage(const WaterLevelPage()),
      onWeatherPressed: () => _openPage(const WeatherPage()),
      onCommunityPressed: () => widget.onNavigate(3),
      onAiPressed: () => _openPage(const FishingInsightsPage()),
    );
  }

  Widget _buildLandscapePhone(HomePremiumLayout layout) {
    final contentHorizontalPadding = layout.horizontalPadding * .60;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: contentHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(layout),
          _buildLocationBridge(layout),
          SizedBox(height: layout.sectionGap * .04),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 58, child: _homeMap),
                SizedBox(width: layout.sectionGap),
                Expanded(
                  flex: 42,
                  child: SingleChildScrollView(
                    controller: _landscapeDashboardController,
                    physics: const BouncingScrollPhysics(),
                    child: _buildDashboard(layout),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: layout.bottomSafeClearance),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF0F1115),
      drawer: HomeSideMenu(onNavigate: widget.onNavigate),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
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
            final layout = HomePremiumLayout.fromViewport(
              context,
              viewportSize: viewportSize,
              systemSafeArea: MediaQuery.viewPaddingOf(context),
              bottomNavigationOverlaysBody: false,
            );
            final compactFirstViewport = layout.isPortrait && !layout.isTablet;
            final contentHorizontalPadding = layout.horizontalPadding * .60;
            const topSpacing = 0.0;
            final headerMapSpacing = layout.sectionGap * .04;
            const locationBridgeHeight = 18.0;
            final mapDashboardSpacing = PremiumDashboard.sectionSpacingFor(
              layout,
            );
            final desiredMapHeight = layout.heroMapHeight * 1.20;
            final reservedFirstViewportHeight =
                topSpacing +
                (layout.headerHeight * .70) +
                locationBridgeHeight +
                headerMapSpacing +
                mapDashboardSpacing +
                PremiumDashboard.primaryViewportHeightFor(layout) +
                (layout.sectionGap * .20);
            final availableMapHeight =
                layout.usableHeight - reservedFirstViewportHeight;
            final heroMapHeight = compactFirstViewport
                ? availableMapHeight.clamp(0.0, desiredMapHeight).toDouble()
                : layout.heroMapHeight * 1.08;

            if (layout.isLandscapePhone) {
              return _buildLandscapePhone(layout);
            }

            return SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: contentHorizontalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: topSpacing),
                      _buildHeader(layout),
                      _buildLocationBridge(layout),
                      SizedBox(height: headerMapSpacing),
                      SizedBox(height: heroMapHeight, child: _homeMap),
                      SizedBox(height: mapDashboardSpacing),
                      _buildDashboard(layout),
                      SizedBox(height: layout.bottomSafeClearance),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
