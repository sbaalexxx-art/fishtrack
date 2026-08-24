import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/context/selected_context.dart';
import '../../core/navigation/app_destination.dart';
import '../../core/navigation/app_navigator.dart';
import '../../core/theme/fluviai_commercial_tokens.dart';
import '../../services/auth_service.dart';

/// Canonical secondary navigation for FluviAI.
///
/// Primary destinations remain in Home and the bottom navigation. This drawer
/// deliberately exposes only personal, tool, account, rules, support, and legal
/// destinations. The identity header is informational and is not a second
/// Profile affordance.
class HomeSideMenu extends ConsumerStatefulWidget {
  const HomeSideMenu({super.key});

  @override
  ConsumerState<HomeSideMenu> createState() => _HomeSideMenuState();
}

class _HomeSideMenuState extends ConsumerState<HomeSideMenu> {
  int? _expandedFamily = 0;

  void _openDestination(AppDestination destination) {
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    navigator.pop();
    unawaited(AppNavigator.open(navigationContext, destination));
  }

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final user = const AuthService().currentUser;
    final rawName = user?.userMetadata?['full_name']?.toString().trim();
    final displayName = rawName != null && rawName.isNotEmpty
        ? rawName
        : (user == null
              ? (isRomanian ? 'Cont FluviAI' : 'FluviAI account')
              : (isRomanian ? 'Pescar FluviAI' : 'FluviAI angler'));
    final email =
        user?.email ??
        (isRomanian ? 'Autentificare necesară' : 'Sign in required');
    final isPremium =
        ref.watch(fluviAccessTierProvider) == FluviAccessTier.premium;
    final families = _families(isRomanian, isPremium);
    final colors = FluviAIThemeColors.of(context);

    return Drawer(
      key: const ValueKey('home-more-drawer'),
      width: MediaQuery.sizeOf(context).width.clamp(300, 390).toDouble(),
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            _brandHeader(),
            _identityHeader(
              displayName: displayName,
              email: email,
              initials: _initials(displayName),
              isPremium: isPremium,
            ),
            Divider(height: 1, thickness: 1, color: colors.borderSoft),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('home-more-scroll'),
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: families.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, thickness: 1, color: colors.borderSoft),
                itemBuilder: (context, index) {
                  final family = families[index];
                  return _familyBlock(
                    index: index,
                    family: family,
                    expanded: _expandedFamily == index,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_DrawerFamily> _families(bool isRomanian, bool isPremium) => [
    _DrawerFamily(
      title: isRomanian ? 'Apele mele' : 'My waters',
      icon: Icons.bookmark_outline_rounded,
      items: [
        _DrawerItem(
          AppDestination.favorites,
          isRomanian ? 'Apele și locurile salvate' : 'Saved waters & places',
        ),
        _DrawerItem(
          AppDestination.myCatches,
          isRomanian ? 'Capturile mele' : 'My catches',
        ),
        _DrawerItem(
          AppDestination.journal,
          isRomanian ? 'Jurnal de pescuit' : 'Fishing journal',
        ),
        _DrawerItem(
          AppDestination.myReports,
          isRomanian ? 'Rapoartele mele' : 'My reports',
        ),
      ],
    ),
    _DrawerFamily(
      title: isRomanian ? 'Instrumente' : 'Tools',
      icon: Icons.handyman_outlined,
      items: [
        _DrawerItem(
          AppDestination.utilities,
          isRomanian ? 'Instrumente' : 'Utilities',
        ),
        _DrawerItem(AppDestination.alerts, isRomanian ? 'Alerte' : 'Alerts'),
        _DrawerItem(
          AppDestination.notificationPreferences,
          isRomanian ? 'Preferințe notificări' : 'Notification preferences',
        ),
      ],
    ),
    _DrawerFamily(
      title: isRomanian ? 'Reguli & siguranță' : 'Rules & safety',
      icon: Icons.health_and_safety_outlined,
      items: [
        _DrawerItem(
          AppDestination.regulations,
          isRomanian
              ? 'Permise, reguli și siguranță'
              : 'Permits, rules & safety',
        ),
      ],
    ),
    _DrawerFamily(
      title: isRomanian ? 'Cont & aplicație' : 'Account & app',
      icon: Icons.person_outline_rounded,
      items: [
        _DrawerItem(AppDestination.profile, isRomanian ? 'Profil' : 'Profile'),
        _DrawerItem(
          AppDestination.accountSecurity,
          isRomanian ? 'Cont și securitate' : 'Account & security',
        ),
        _DrawerItem(
          AppDestination.premium,
          'Premium',
          badge: isPremium
              ? (isRomanian ? 'ACTIV' : 'ACTIVE')
              : (isRomanian ? 'VEZI' : 'VIEW'),
        ),
        _DrawerItem(
          AppDestination.settings,
          isRomanian ? 'Setări' : 'Settings',
        ),
      ],
    ),
    _DrawerFamily(
      title: isRomanian ? 'Ajutor & legal' : 'Help & legal',
      icon: Icons.help_outline_rounded,
      items: [
        _DrawerItem(
          AppDestination.support,
          isRomanian
              ? 'Ajutor, feedback și contact'
              : 'Help, feedback & contact',
        ),
        _DrawerItem(
          AppDestination.privacy,
          isRomanian ? 'Confidențialitate' : 'Privacy',
        ),
        _DrawerItem(AppDestination.terms, isRomanian ? 'Termeni' : 'Terms'),
        _DrawerItem(
          AppDestination.licences,
          isRomanian ? 'Licențe' : 'Licences',
        ),
        _DrawerItem(
          AppDestination.legal,
          isRomanian ? 'Centru legal' : 'Legal hub',
        ),
        _DrawerItem(
          AppDestination.about,
          isRomanian ? 'Despre FluviAI' : 'About FluviAI',
        ),
      ],
    ),
  ];

  Widget _brandHeader() {
    final colors = FluviAIThemeColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Fluvi ',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  TextSpan(
                    text: 'AI',
                    style: TextStyle(color: accent),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              key: const ValueKey('drawer-close'),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.close_rounded,
                color: colors.textPrimary,
                size: 21,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityHeader({
    required String displayName,
    required String email,
    required String initials,
    required bool isPremium,
  }) {
    final colors = FluviAIThemeColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      key: const ValueKey('drawer-identity-header'),
      label: '$displayName, ${isPremium ? 'PRO' : 'FREE'}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 18, 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.backgroundRaised,
                shape: BoxShape.circle,
                border: Border.all(color: accent),
              ),
              child: Text(
                initials,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isPremium ? 'PRO' : 'FREE',
              style: TextStyle(
                color: isPremium
                    ? Theme.of(context).colorScheme.tertiary
                    : accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: .35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _familyBlock({
    required int index,
    required _DrawerFamily family,
    required bool expanded,
  }) {
    final colors = FluviAIThemeColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            key: ValueKey('burger-family-$index'),
            onTap: () => setState(() {
              _expandedFamily = expanded ? null : index;
            }),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(
                      family.icon,
                      color: expanded ? accent : colors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        family.title,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      family.items.length.toString(),
                      style: TextStyle(color: colors.textMuted, fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: colors.textSecondary,
                      size: 21,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded)
          for (final item in family.items) _destinationItem(item),
      ],
    );
  }

  Widget _destinationItem(_DrawerItem item) {
    final colors = FluviAIThemeColors.of(context);
    return Semantics(
      button: true,
      label: item.label,
      child: InkWell(
        key: ValueKey('more-${item.destination.name}'),
        onTap: () => _openDestination(item.destination),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.only(left: 52, right: 17),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (item.badge != null) ...[
                  Text(
                    item.badge!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textMuted,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .toList(growable: false);
    if (words.isEmpty) return 'FA';
    return words.map((word) => word.substring(0, 1).toUpperCase()).join();
  }
}

class _DrawerFamily {
  const _DrawerFamily({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_DrawerItem> items;
}

class _DrawerItem {
  const _DrawerItem(this.destination, this.label, {this.badge});

  final AppDestination destination;
  final String label;
  final String? badge;
}
