import 'package:flutter/material.dart';

import '../widgets/home_premium/dashboard.dart';
import '../widgets/home_premium/home_header.dart';
import '../widgets/home_premium/home_map.dart';
import '../widgets/home_premium/home_premium_layout.dart';
import 'water_level_page.dart';
import 'weather_page.dart';
import 'developer_mode_page.dart';
import 'fishing_insights_page.dart';
import 'notifications_page.dart';

class HomePremiumPage extends StatelessWidget {
  const HomePremiumPage({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final scaffoldKey = GlobalKey<ScaffoldState>();

    void openPage(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    return Scaffold(
      key: scaffoldKey,
      backgroundColor: const Color(0xFF0F1115),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.map_rounded),
                title: const Text('Map'),
                onTap: () => onNavigate(1),
              ),
              ListTile(
                leading: const Icon(Icons.wb_sunny_rounded),
                title: const Text('Weather'),
                onTap: () => onNavigate(2),
              ),
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: const Text('Community'),
                onTap: () => onNavigate(3),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_rounded),
                title: const Text('Favorites'),
                onTap: () => onNavigate(4),
              ),
              ListTile(
                leading: const Icon(Icons.person_rounded),
                title: const Text('Profile'),
                onTap: () => onNavigate(5),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }

            return SingleChildScrollView(
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
                      HomePremiumHeader(
                        notificationCount: 0,
                        onMenuPressed: () =>
                            scaffoldKey.currentState?.openDrawer(),
                        onNotificationPressed: () =>
                            openPage(const NotificationsPage()),
                        onLogoLongPress: () =>
                            openPage(const DeveloperModePage()),
                      ),
                      SizedBox(height: layout.sectionGap * .5),
                      SizedBox(
                        height: layout.heroMapHeight,
                        child: const HomePremiumMap(),
                      ),
                      SizedBox(height: layout.sectionGap),
                      PremiumDashboard(
                        onWaterLevelPressed: () =>
                            openPage(const WaterLevelPage()),
                        onWeatherPressed: () => openPage(const WeatherPage()),
                        onCommunityPressed: () => onNavigate(3),
                        onAiPressed: () =>
                            openPage(const FishingInsightsPage()),
                      ),
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
