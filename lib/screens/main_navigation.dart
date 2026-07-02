import 'package:flutter/material.dart';

import 'favorites_page.dart';
import 'home_page.dart';
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
    HomePage(),
    MapPage(),
    WeatherPage(),
    ReportsPage(),
    FavoritesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: _pages[_selectedIndex],
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1B),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _item(Icons.home_rounded, 0),
              _item(Icons.map_rounded, 1),

              GestureDetector(
                onTap: () {
                  // TODO Add Catch
                },
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E88E5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 30),
                ),
              ),

              _item(Icons.campaign_rounded, 3),
              _item(Icons.person_rounded, 5),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(IconData icon, int index) {
    final selected = _selectedIndex == index;

    return IconButton(
      onPressed: () {
        setState(() => _selectedIndex = index);
      },
      icon: Icon(
        icon,
        size: 28,
        color: selected ? const Color(0xFF1E88E5) : Colors.white54,
      ),
    );
  }
}
