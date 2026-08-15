import 'package:flutter/material.dart';

import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/theme/fluviai_commercial_tokens.dart';

class FluviAIActivityHubPage extends StatefulWidget {
  const FluviAIActivityHubPage({super.key});

  @override
  State<FluviAIActivityHubPage> createState() => _FluviAIActivityHubPageState();
}

class _FluviAIActivityHubPageState extends State<FluviAIActivityHubPage> {
  bool _historySelected = false;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    String copy(String ro, String en) => isRomanian ? ro : en;

    return ColoredBox(
      key: const ValueKey('activity-hub-page'),
      color: FluviAIThemeColors.of(context).background,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey<String>('activity-hub-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ActivityHeader(
                  title: copy('Activitate', 'Activity'),
                  subtitle: copy(
                    'Notificări și istoricul tău de pescuit',
                    'Notifications and your fishing history',
                  ),
                  onNotifications: () => AppNavigator.open<void>(
                    context,
                    AppDestination.notifications,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ActivitySegments(
                  historySelected: _historySelected,
                  onNotifications: () =>
                      setState(() => _historySelected = false),
                  onHistory: () => setState(() => _historySelected = true),
                  notificationsLabel: copy('Notificări', 'Notifications'),
                  historyLabel: copy('Istoricul meu', 'My history'),
                ),
              ),
            ),
            if (!_historySelected) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _ActivitySectionLabel(copy('PRIORITAR', 'PRIORITY')),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _PriorityActivityCard(
                    title: copy(
                      'Alertele importante sunt într-un singur loc',
                      'Important alerts are kept in one place',
                    ),
                    subtitle: copy(
                      'Nivel, vreme și siguranță · fără valori demonstrative',
                      'Water, weather and safety · no demo values',
                    ),
                    onTap: () =>
                        AppNavigator.open<void>(context, AppDestination.alerts),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _ActivitySectionLabel(copy('RECENTE', 'RECENT')),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    _ActivityUpdateCard(
                      keyName: 'activity-community',
                      icon: Icons.forum_outlined,
                      accent: FluviAICommercialTokens.brandFocus,
                      title: copy('Comunitate', 'Community'),
                      subtitle: copy(
                        'Puls local, rapoarte și capturi reale',
                        'Local pulse, reports and real catches',
                      ),
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.community,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActivityUpdateCard(
                      keyName: 'activity-my-reports',
                      icon: Icons.outlined_flag_rounded,
                      accent: FluviAICommercialTokens.warning,
                      title: copy('Rapoartele mele', 'My reports'),
                      subtitle: copy(
                        'Active, expirate și confirmări',
                        'Active, expired and confirmations',
                      ),
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.myReports,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActivityUpdateCard(
                      keyName: 'activity-my-catches',
                      icon: Icons.set_meal_outlined,
                      accent: FluviAICommercialTokens.waterStable,
                      title: copy('Capturile mele', 'My catches'),
                      subtitle: copy(
                        'Fotografii, măsurători și istoric',
                        'Photos, measurements and history',
                      ),
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.myCatches,
                      ),
                    ),
                  ]),
                ),
              ),
            ] else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _ActivitySectionLabel(
                    copy('ISTORIC PERSONAL', 'PERSONAL HISTORY'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    _ActivityUpdateCard(
                      keyName: 'activity-journal',
                      icon: Icons.menu_book_outlined,
                      accent: FluviAICommercialTokens.premium,
                      title: copy('Jurnal de pescuit', 'Fishing journal'),
                      subtitle: copy(
                        'Capturi și rapoarte personale',
                        'Personal catches and reports',
                      ),
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.journal,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActivityUpdateCard(
                      keyName: 'activity-history-reports',
                      icon: Icons.inventory_2_outlined,
                      accent: FluviAICommercialTokens.warning,
                      title: copy('Arhiva rapoartelor', 'Report archive'),
                      subtitle: copy(
                        'Rapoartele proprii și starea lor',
                        'Your reports and their status',
                      ),
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.myReports,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActivityUpdateCard(
                      keyName: 'activity-history-catches',
                      icon: Icons.photo_library_outlined,
                      accent: FluviAICommercialTokens.waterStable,
                      title: copy('Istoric capturi', 'Catch history'),
                      subtitle: copy(
                        'Capturile salvate în contul tău',
                        'Catches saved to your account',
                      ),
                      onTap: () => AppNavigator.open<void>(
                        context,
                        AppDestination.myCatches,
                      ),
                    ),
                  ]),
                ),
              ),
            ],
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ActivitySummaryCard(
                  title: copy(
                    'Jurnal, capturi și rapoarte',
                    'Journal, catches and reports',
                  ),
                  subtitle: copy(
                    'Deschide jurnalul și activitatea personală',
                    'Open your journal and personal activity',
                  ),
                  onTap: () =>
                      AppNavigator.open<void>(context, AppDestination.journal),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _NotificationDeliveryCard(
                  title: copy('Livrare notificări', 'Notification delivery'),
                  subtitle: copy(
                    'Categorii, grupare și Nu deranja',
                    'Categories, grouping and Do Not Disturb',
                  ),
                  onTap: () => AppNavigator.open<void>(
                    context,
                    AppDestination.notificationPreferences,
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({
    required this.title,
    required this.subtitle,
    required this.onNotifications,
  });

  final String title;
  final String subtitle;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: FluviAIThemeColors.of(context).textPrimary,
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: FluviAIThemeColors.of(context).textSecondary,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Semantics(
        button: true,
        label: 'Notificări',
        child: SizedBox.square(
          dimension: 44,
          child: Material(
            key: const ValueKey('activity-notifications-action'),
            color: FluviAIThemeColors.of(context).surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onNotifications,
              child: Icon(
                Icons.notifications_none_rounded,
                color: FluviAIThemeColors.of(context).textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _ActivitySegments extends StatelessWidget {
  const _ActivitySegments({
    required this.historySelected,
    required this.onNotifications,
    required this.onHistory,
    required this.notificationsLabel,
    required this.historyLabel,
  });

  final bool historySelected;
  final VoidCallback onNotifications;
  final VoidCallback onHistory;
  final String notificationsLabel;
  final String historyLabel;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: FluviAIThemeColors.of(context).surfaceStrong,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: FluviAIThemeColors.of(context).border),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ActivitySegment(
            label: notificationsLabel,
            selected: !historySelected,
            onTap: onNotifications,
          ),
        ),
        Expanded(
          child: _ActivitySegment(
            label: historyLabel,
            selected: historySelected,
            onTap: onHistory,
          ),
        ),
      ],
    ),
  );
}

class _ActivitySegment extends StatelessWidget {
  const _ActivitySegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? Color.alphaBlend(
            FluviAICommercialTokens.brandFocus.withValues(alpha: .13),
            FluviAIThemeColors.of(context).surfaceRaised,
          )
        : Colors.transparent,
    borderRadius: BorderRadius.circular(11),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected
                ? FluviAICommercialTokens.brandFocus
                : FluviAIThemeColors.of(context).textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _ActivitySectionLabel extends StatelessWidget {
  const _ActivitySectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: FluviAIThemeColors.of(context).textSecondary,
      fontFamily: FluviAICommercialTokens.monoFontFamily,
      fontSize: 9,
      fontWeight: FontWeight.w500,
      letterSpacing: .25,
    ),
  );
}

class _PriorityActivityCard extends StatelessWidget {
  const _PriorityActivityCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ActivitySurface(
    key: const ValueKey('activity-alerts'),
    borderColor: FluviAICommercialTokens.warning.withValues(alpha: .38),
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              FluviAICommercialTokens.warning.withValues(alpha: .10),
              FluviAIThemeColors.of(context).surfaceRaised,
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: FluviAICommercialTokens.warning.withValues(alpha: .5),
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.warning_amber_rounded,
            color: FluviAICommercialTokens.warning,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textPrimary,
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textSecondary,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.chevron_right_rounded,
          color: FluviAICommercialTokens.brandFocus,
          size: 20,
        ),
      ],
    ),
  );
}

class _ActivityUpdateCard extends StatelessWidget {
  const _ActivityUpdateCard({
    required this.keyName,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ActivitySurface(
    key: ValueKey(keyName),
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textSecondary,
                  fontSize: 10.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: FluviAICommercialTokens.brandFocus,
          size: 18,
        ),
      ],
    ),
  );
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ActivitySurface(
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REZUMAT PERSONAL',
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textSecondary,
                  fontFamily: FluviAICommercialTokens.monoFontFamily,
                  fontSize: 9,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: FluviAICommercialTokens.brandFocus,
          size: 19,
        ),
      ],
    ),
  );
}

class _NotificationDeliveryCard extends StatelessWidget {
  const _NotificationDeliveryCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _ActivitySurface(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  color: FluviAIThemeColors.of(context).textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: FluviAICommercialTokens.brandFocus,
          size: 18,
        ),
      ],
    ),
  );
}

class _ActivitySurface extends StatelessWidget {
  const _ActivitySurface({
    super.key,
    required this.child,
    required this.onTap,
    required this.padding,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Ink(
      decoration: BoxDecoration(
        color: FluviAIThemeColors.of(context).surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? FluviAIThemeColors.of(context).border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}
