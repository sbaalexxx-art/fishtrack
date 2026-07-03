import 'dart:ui';

import 'package:flutter/material.dart';

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
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFF0F1115),
      body: _pages[_selectedIndex],

      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              height: screenHeight * .072,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.07),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withOpacity(.08)),
              ),
              child: Row(
                children: [
                  Expanded(child: _item(Icons.home_rounded, 0)),

                  Expanded(child: _item(Icons.map_rounded, 1)),

                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: () {},
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFF67D04B),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF67D04B).withOpacity(.35),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 32,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Expanded(child: _item(Icons.analytics_rounded, 3)),

                  Expanded(child: _item(Icons.person_rounded, 5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, int index) {
    final selected = _selectedIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? const Color(0xFF67D04B).withOpacity(.12)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 26,
          color: selected ? const Color(0xFF67D04B) : Colors.white60,
        ),
      ),
    );
  }
}
