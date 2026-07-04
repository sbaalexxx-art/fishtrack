import 'dart:ui';

import 'package:flutter/material.dart';

import '../widgets/home_premium/home_premium_layout.dart';
import 'favorites_page.dart';
import 'home_premium_page.dart';
import 'map_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'weather_page.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomePremiumPage(),
    MapPage(),
    WeatherPage(),
    ReportsPage(),
    FavoritesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFF0F1115),
      body: _pages[_selectedIndex],

      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              height: layout.bottomNavHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF171C24).withValues(alpha: .92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: .09)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .34),
                    blurRadius: 24,
                    spreadRadius: -8,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(child: _item(Icons.home_rounded, 'Home', 0, layout)),

                  Expanded(child: _item(Icons.map_rounded, 'Map', 1, layout)),

                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: layout.bottomNavHeight - 12,
                          height: layout.bottomNavHeight - 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF12D8D6),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF12D8D6,
                                ).withValues(alpha: .35),
                                blurRadius: 20,
                                spreadRadius: -1,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.add,
                            size: 25 * layout.iconScale,
                            color: const Color(0xFF0F1115),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Expanded(
                    child: _item(Icons.bar_chart_rounded, 'Reports', 3, layout),
                  ),

                  Expanded(
                    child: _item(Icons.person_rounded, 'Profile', 5, layout),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    IconData icon,
    String label,
    int index,
    HomePremiumLayout layout,
  ) {
    final selected = _selectedIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 34,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected
                    ? const Color(0xFF12D8D6).withValues(alpha: .10)
                    : Colors.transparent,
              ),
              child: Icon(
                icon,
                size: 20 * layout.iconScale,
                color: selected ? const Color(0xFF12D8D6) : Colors.white54,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                color: selected ? const Color(0xFF12D8D6) : Colors.white54,
                fontSize: 9 * layout.bodyFontScale,
                height: 1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
