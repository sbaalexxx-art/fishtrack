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
  Orientation? _orientation;

  @override
  void initState() {
    super.initState();
    _homeMap = HomePremiumMap(key: _homeMapKey);
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

  Widget _buildHeader() {
    return HomePremiumHeader(
      notificationCount: 0,
      onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
      onNotificationPressed: () => _openPage(const NotificationsPage()),
      onLogoLongPress: BuildModeService.isDeveloperVisible
          ? () => _openPage(const DeveloperModePage())
          : null,
    );
  }

  Widget _buildDashboard() {
    return PremiumDashboard(
      onWaterLevelPressed: () => _openPage(const WaterLevelPage()),
      onWeatherPressed: () => _openPage(const WeatherPage()),
      onCommunityPressed: () => widget.onNavigate(3),
      onAiPressed: () => _openPage(const FishingInsightsPage()),
    );
  }

  Widget _buildLandscapePhone(HomePremiumLayout layout) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: layout.sectionGap * .25),
          _buildHeader(),
          SizedBox(height: layout.sectionGap * .5),
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
                    child: _buildDashboard(),
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
                    horizontal: layout.horizontalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: layout.sectionGap * .25),
                      _buildHeader(),
                      SizedBox(height: layout.sectionGap * .5),
                      SizedBox(height: layout.heroMapHeight, child: _homeMap),
                      SizedBox(height: layout.sectionGap),
                      _buildDashboard(),
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
