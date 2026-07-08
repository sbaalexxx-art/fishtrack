import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
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
                'FluviAI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _section(context.l10n.mainSection),
            _item(
              context,
              Icons.home_rounded,
              context.l10n.home,
              () => _selectTab(context, 0),
            ),
            _item(
              context,
              Icons.map_rounded,
              context.l10n.map,
              () => _selectTab(context, 1),
            ),
            _item(
              context,
              Icons.water_rounded,
              context.l10n.waterLevels,
              () => _openPage(context, const WaterLevelPage()),
            ),
            _item(
              context,
              Icons.wb_sunny_rounded,
              context.l10n.weather,
              () => _selectTab(context, 2),
            ),
            _item(
              context,
              Icons.groups_rounded,
              context.l10n.community,
              () => _selectTab(context, 3),
            ),
            _item(
              context,
              Icons.history_rounded,
              context.l10n.reportsArchive,
              () => _openPage(context, const ReportsArchivePage()),
            ),
            _item(
              context,
              Icons.auto_awesome_rounded,
              context.l10n.aiFishingInsights,
              () => _openPage(context, const FishingInsightsPage()),
            ),
            _section(context.l10n.myFishing),
            _item(
              context,
              Icons.add_circle_outline_rounded,
              context.l10n.addCatch,
              () => _openPage(context, const AddCatchPage()),
            ),
            _placeholderItem(context, Icons.phishing_rounded, context.l10n.myCatches),
            _item(
              context,
              Icons.favorite_rounded,
              context.l10n.favorites,
              () => _selectTab(context, 4),
            ),
            _placeholderItem(context, Icons.menu_book_rounded, context.l10n.fishingDiary),
            _section(context.l10n.useful),
            _placeholderItem(context, Icons.badge_outlined, context.l10n.fishingPermit),
            _placeholderItem(context, Icons.gavel_rounded, context.l10n.regulations),
            _placeholderItem(
              context,
              Icons.event_busy_rounded,
              context.l10n.closedSeason,
            ),
            _placeholderItem(
              context,
              Icons.straighten_rounded,
              context.l10n.minimumLegalSizes,
            ),
            _placeholderItem(
              context,
              Icons.shield_outlined,
              context.l10n.protectedSpecies,
            ),
            _placeholderItem(
              context,
              Icons.format_list_numbered_rounded,
              context.l10n.dailyCatchLimits,
            ),
            _placeholderItem(
              context,
              Icons.nature_people_outlined,
              context.l10n.protectedAreas,
            ),
            _placeholderItem(context, Icons.report_outlined, context.l10n.reportPoaching),
            _placeholderItem(context, Icons.nightlight_round, context.l10n.solunar),
            _placeholderItem(
              context,
              Icons.calendar_month_rounded,
              context.l10n.fishingCalendar,
            ),
            _placeholderItem(context, Icons.link_rounded, context.l10n.knots),
            _placeholderItem(
              context,
              Icons.swap_horiz_rounded,
              context.l10n.unitConversions,
            ),
            _placeholderItem(
              context,
              Icons.contact_phone_outlined,
              context.l10n.authorityContacts,
            ),
            _section(context.l10n.account),
            _item(
              context,
              Icons.person_rounded,
              context.l10n.profile,
              () => _selectTab(context, 5),
            ),
            _item(
              context,
              Icons.notifications_rounded,
              context.l10n.notifications,
              () => _openPage(context, const NotificationsPage()),
            ),
            _item(
              context,
              Icons.settings_rounded,
              context.l10n.settings,
              () => _openPage(context, const SettingsPage()),
            ),
            _placeholderItem(
              context,
              Icons.workspace_premium_rounded,
              context.l10n.premium,
            ),
            _section(context.l10n.support),
            _placeholderItem(context, Icons.help_outline_rounded, context.l10n.helpFaq),
            _placeholderItem(
              context,
              Icons.support_agent_rounded,
              context.l10n.contactSupport,
            ),
            _placeholderItem(context, Icons.rate_review_outlined, context.l10n.feedback),
            _placeholderItem(
              context,
              Icons.privacy_tip_outlined,
              context.l10n.privacyPolicy,
            ),
            _placeholderItem(context, Icons.description_outlined, context.l10n.terms),
            _placeholderItem(
              context,
              Icons.info_outline_rounded,
              context.l10n.aboutApp,
            ),
            if (BuildModeService.isDeveloperVisible) ...[
              const Divider(
                color: Colors.white12,
                height: 32,
                indent: 16,
                endIndent: 16,
              ),
              _section(context.l10n.developer),
              _item(
                context,
                Icons.developer_mode_rounded,
                context.l10n.developerMode,
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
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white),
      ),
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
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.l10n.featureComingSoon,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
}
