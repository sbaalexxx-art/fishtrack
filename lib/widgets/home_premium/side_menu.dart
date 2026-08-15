import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/context/selected_context.dart';
import '../../core/navigation/app_destination.dart';
import '../../core/navigation/app_navigator.dart';
import '../../services/auth_service.dart';

/// Canonical FluviAI drawer based on Figma node 2450:2.
///
/// The inventory stays complete even when a capability is not yet backed by a
/// remote service. Every row resolves through [AppNavigator], so the drawer
/// never contains a decorative or empty interaction.
class HomeSideMenu extends ConsumerWidget {
  const HomeSideMenu({super.key});

  static const _background = Color(0xFF040C18);
  static const _surface = Color(0xFF0A1B2D);
  static const _cyan = Color(0xFF00E5FF);
  static const _muted = Color(0xFF94A3B8);
  static const _dim = Color(0xFF475569);
  static const _gold = Color(0xFFFFC857);

  void _openDestination(BuildContext context, AppDestination destination) {
    final navigator = Navigator.of(context);
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      AppNavigator.open(navigator.context, destination);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final initials = _initials(displayName);
    final isPremium =
        ref.watch(fluviAccessTierProvider) == FluviAccessTier.premium;

    return Drawer(
      key: const ValueKey('home-more-drawer'),
      width: MediaQuery.sizeOf(context).width.clamp(300, 390).toDouble(),
      backgroundColor: _background,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 16,
              top: 118,
              bottom: 96,
              child: Container(width: 2, color: _cyan.withValues(alpha: .10)),
            ),
            ListView(
              key: const ValueKey('home-more-scroll'),
              padding: const EdgeInsets.only(bottom: 22),
              children: [
                _brandHeader(context),
                _accountBlock(
                  context,
                  displayName: displayName,
                  email: email,
                  initials: initials,
                  isPremium: isPremium,
                ),
                _divider(),
                _section(isRomanian ? 'Pescuitul meu' : 'My fishing'),
                _destinationItem(
                  context,
                  AppDestination.myCatches,
                  label: isRomanian ? 'Capturile mele' : 'My catches',
                ),
                _destinationItem(
                  context,
                  AppDestination.favorites,
                  label: isRomanian
                      ? 'Apele mele și locuri salvate'
                      : 'My waters & saved places',
                ),
                _destinationItem(
                  context,
                  AppDestination.journal,
                  label: isRomanian ? 'Jurnal de pescuit' : 'Fishing journal',
                ),
                _destinationItem(
                  context,
                  AppDestination.myReports,
                  label: isRomanian ? 'Rapoartele mele' : 'My reports',
                ),
                _divider(),
                _section(isRomanian ? 'Instrumente' : 'Tools'),
                _destinationItem(
                  context,
                  AppDestination.alerts,
                  label: isRomanian
                      ? 'Alerte și notificări'
                      : 'Alerts & notifications',
                ),
                _destinationItem(
                  context,
                  AppDestination.notificationPreferences,
                  label: isRomanian ? 'Preferințe notificări' : 'Notifications',
                ),
                _destinationItem(context, AppDestination.search),
                _destinationItem(
                  context,
                  AppDestination.water,
                  label: isRomanian ? 'Centrul apei' : 'Water hub',
                ),
                _destinationItem(
                  context,
                  AppDestination.weather,
                  label: isRomanian ? 'Meteo și solunar' : 'Weather & solunar',
                ),
                _destinationItem(
                  context,
                  AppDestination.fluvi,
                  label: isRomanian ? 'Centrul Fluvi' : 'Fluvi Hub',
                ),
                _destinationItem(context, AppDestination.askFluvi),
                _destinationItem(context, AppDestination.toolkit),
                _destinationItem(
                  context,
                  AppDestination.permit,
                  label: isRomanian ? 'Permis de pescuit' : 'Fishing permit',
                ),
                _destinationItem(
                  context,
                  AppDestination.regulations,
                  label: isRomanian
                      ? 'Reglementări și dimensiuni'
                      : 'Regulations & sizes',
                ),
                _destinationItem(context, AppDestination.safety),
                _divider(),
                _section(isRomanian ? 'Cont' : 'Account'),
                _destinationItem(context, AppDestination.profile),
                _destinationItem(
                  context,
                  AppDestination.accountSecurity,
                  label: isRomanian
                      ? 'Cont și securitate'
                      : 'Account & security',
                ),
                _destinationItem(
                  context,
                  AppDestination.premium,
                  label: isRomanian ? 'Premium' : 'Premium',
                  badge: isPremium
                      ? (isRomanian ? 'Activ' : 'Active')
                      : (isRomanian ? 'Vezi' : 'View'),
                  badgeColor: isPremium ? _cyan : _gold,
                ),
                _destinationItem(context, AppDestination.settings),
                _destinationItem(
                  context,
                  AppDestination.settings,
                  label: isRomanian ? 'Aspect' : 'Appearance',
                  keySuffix: 'appearance',
                ),
                _destinationItem(
                  context,
                  AppDestination.settings,
                  label: isRomanian ? 'Limbă / Regiune' : 'Language / Region',
                  keySuffix: 'language-region',
                ),
                _divider(),
                _section(isRomanian ? 'Suport' : 'Support'),
                _destinationItem(
                  context,
                  AppDestination.support,
                  label: isRomanian ? 'Ajutor și FAQ' : 'Help & FAQ',
                  keySuffix: 'help-faq',
                ),
                _destinationItem(
                  context,
                  AppDestination.support,
                  label: isRomanian ? 'Trimite feedback' : 'Send feedback',
                  keySuffix: 'send-feedback',
                ),
                _destinationItem(
                  context,
                  AppDestination.support,
                  label: isRomanian ? 'Contactează-ne' : 'Contact us',
                  keySuffix: 'contact-us',
                ),
                _divider(),
                _section('Legal', color: _dim),
                _destinationItem(context, AppDestination.privacy),
                _destinationItem(context, AppDestination.terms),
                _destinationItem(context, AppDestination.licences),
                _destinationItem(context, AppDestination.legal),
                _destinationItem(context, AppDestination.about),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Versiune afișată din build',
                    style: TextStyle(color: _dim, fontSize: 9),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _brandHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 14, 8),
    child: Row(
      children: [
        const Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Fluvi ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'AI',
                  style: TextStyle(color: _cyan),
                ),
              ],
            ),
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: Colors.white.withValues(alpha: .04),
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: .10)),
            ),
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _accountBlock(
    BuildContext context, {
    required String displayName,
    required String email,
    required String initials,
    required bool isPremium,
  }) => InkWell(
    key: const ValueKey('drawer-account-summary'),
    onTap: () => _openDestination(context, AppDestination.profile),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 20, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surface,
              shape: BoxShape.circle,
              border: Border.all(color: _cyan, width: 2),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: _cyan,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _badge(
                      isPremium ? 'PRO' : 'FREE',
                      isPremium ? _gold : _cyan,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _section(String title, {Color color = _muted}) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 20, 7),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: .25,
      ),
    ),
  );

  Widget _divider() =>
      Container(height: 1, color: Colors.white.withValues(alpha: .04));

  Widget _destinationItem(
    BuildContext context,
    AppDestination destination, {
    String? label,
    String? keySuffix,
    String? badge,
    Color badgeColor = _cyan,
  }) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final definition = AppDestinationRegistry.of(destination);
    final title = label ?? definition.title(isRomanian);
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        key: ValueKey('more-${keySuffix ?? destination.name}'),
        onTap: () => _openDestination(context, destination),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  _badge(badge, badgeColor),
                  const SizedBox(width: 10),
                ],
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: .85)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
    ),
  );

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
