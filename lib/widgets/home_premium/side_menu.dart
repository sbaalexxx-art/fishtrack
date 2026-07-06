import 'package:flutter/material.dart';

import '../../screens/add_catch_page.dart';
import '../../screens/developer_mode_page.dart';
import '../../screens/fishing_insights_page.dart';
import '../../screens/notifications_page.dart';
import '../../screens/reports_archive_page.dart';
import '../../screens/settings_page.dart';
import '../../screens/water_level_page.dart';
import '../../services/build_mode_service.dart';

class HomeSideMenu extends StatelessWidget {
  const HomeSideMenu({super.key, required this.onNavigate});

  final ValueChanged<int> onNavigate;

  void _selectTab(BuildContext context, int index) {
    Navigator.of(context).pop();
    onNavigate(index);
  }

  void _openPage(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF171C24),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'AIFishMap',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _section('Main'),
            _item(
              context,
              Icons.home_rounded,
              'Home',
              () => _selectTab(context, 0),
            ),
            _item(
              context,
              Icons.map_rounded,
              'Map',
              () => _selectTab(context, 1),
            ),
            _item(
              context,
              Icons.water_rounded,
              'Water Levels',
              () => _openPage(context, const WaterLevelPage()),
            ),
            _item(
              context,
              Icons.wb_sunny_rounded,
              'Weather',
              () => _selectTab(context, 2),
            ),
            _item(
              context,
              Icons.groups_rounded,
              'Community',
              () => _selectTab(context, 3),
            ),
            _item(
              context,
              Icons.history_rounded,
              'Reports Archive',
              () => _openPage(context, const ReportsArchivePage()),
            ),
            _item(
              context,
              Icons.auto_awesome_rounded,
              'AI Fishing Insights',
              () => _openPage(context, const FishingInsightsPage()),
            ),
            _section('My Fishing'),
            _item(
              context,
              Icons.add_circle_outline_rounded,
              'Add Catch',
              () => _openPage(context, const AddCatchPage()),
            ),
            _placeholderItem(context, Icons.phishing_rounded, 'My Catches'),
            _item(
              context,
              Icons.favorite_rounded,
              'Favorites',
              () => _selectTab(context, 4),
            ),
            _placeholderItem(context, Icons.menu_book_rounded, 'Fishing Diary'),
            _section('Useful'),
            _placeholderItem(context, Icons.badge_outlined, 'Fishing Permit'),
            _placeholderItem(context, Icons.gavel_rounded, 'Regulations'),
            _placeholderItem(
              context,
              Icons.event_busy_rounded,
              'Closed Season / Prohibition',
            ),
            _placeholderItem(
              context,
              Icons.straighten_rounded,
              'Minimum Legal Sizes',
            ),
            _placeholderItem(
              context,
              Icons.shield_outlined,
              'Protected Species',
            ),
            _placeholderItem(
              context,
              Icons.format_list_numbered_rounded,
              'Daily Catch Limits',
            ),
            _placeholderItem(
              context,
              Icons.nature_people_outlined,
              'Protected Areas',
            ),
            _placeholderItem(context, Icons.report_outlined, 'Report Poaching'),
            _placeholderItem(context, Icons.nightlight_round, 'Solunar'),
            _placeholderItem(
              context,
              Icons.calendar_month_rounded,
              'Fishing Calendar',
            ),
            _placeholderItem(context, Icons.link_rounded, 'Knots'),
            _placeholderItem(
              context,
              Icons.swap_horiz_rounded,
              'Unit Conversions',
            ),
            _placeholderItem(
              context,
              Icons.contact_phone_outlined,
              'Authority Contacts',
            ),
            _section('Account'),
            _item(
              context,
              Icons.person_rounded,
              'Profile',
              () => _selectTab(context, 5),
            ),
            _item(
              context,
              Icons.notifications_rounded,
              'Notifications',
              () => _openPage(context, const NotificationsPage()),
            ),
            _item(
              context,
              Icons.settings_rounded,
              'Settings',
              () => _openPage(context, const SettingsPage()),
            ),
            _placeholderItem(
              context,
              Icons.workspace_premium_rounded,
              'Premium',
            ),
            _section('Support'),
            _placeholderItem(context, Icons.help_outline_rounded, 'Help & FAQ'),
            _placeholderItem(
              context,
              Icons.support_agent_rounded,
              'Contact Support',
            ),
            _placeholderItem(context, Icons.rate_review_outlined, 'Feedback'),
            _placeholderItem(
              context,
              Icons.privacy_tip_outlined,
              'Privacy Policy',
            ),
            _placeholderItem(context, Icons.description_outlined, 'Terms'),
            _placeholderItem(
              context,
              Icons.info_outline_rounded,
              'About AIFishMap',
            ),
            if (BuildModeService.isDeveloperVisible) ...[
              const Divider(
                color: Colors.white12,
                height: 32,
                indent: 16,
                endIndent: 16,
              ),
              _section('Developer'),
              _item(
                context,
                Icons.developer_mode_rounded,
                'Developer Mode',
                () => _openPage(context, const DeveloperModePage()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF12D8D6),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  Widget _placeholderItem(BuildContext context, IconData icon, String title) {
    if (!BuildModeService.isDeveloperVisible) {
      return const SizedBox.shrink();
    }
    return _item(
      context,
      icon,
      title,
      () => _openPage(context, ComingSoonPage(title: title)),
    );
  }
}

class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This feature is coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
}
