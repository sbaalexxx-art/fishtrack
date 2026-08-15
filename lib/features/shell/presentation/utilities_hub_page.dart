import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../core/context/current_location.dart';
import '../../../core/map/pending_map_camera.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/theme/fluviai_commercial_tokens.dart';
import '../../../core/utility/fluviai_explore_catalog.dart';
import '../../../core/utility/fluviai_utility_registry.dart';
import '../../../features/commercial_home/data/commercial_home_data_source.dart';
import '../../../l10n/l10n.dart';
import '../../../models/station.dart';
import '../../../services/water_service.dart';

class FluviAIUtilitiesHubPage extends ConsumerStatefulWidget {
  const FluviAIUtilitiesHubPage({
    super.key,
    required this.onSelectMainTab,
    this.dataSource,
  });

  final ValueChanged<int> onSelectMainTab;
  final CommercialHomeDataSource? dataSource;

  @override
  ConsumerState<FluviAIUtilitiesHubPage> createState() =>
      _FluviAIUtilitiesHubPageState();
}

class _FluviAIUtilitiesHubPageState
    extends ConsumerState<FluviAIUtilitiesHubPage> {
  final TextEditingController _searchController = TextEditingController();
  final WaterService _waterService = WaterService();
  String _query = '';
  FluviExploreSection? _selectedSection;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Station? _stationArgument(SelectedContext? selected) {
    final stationId = selected?.stationId;
    final latitude = selected?.latitude;
    final longitude = selected?.longitude;
    if (stationId == null || latitude == null || longitude == null) return null;

    final selectedStation = _waterService.selectedStation;
    if (selectedStation?.id == stationId) return selectedStation;
    final automaticStation = _waterService.lastAutomaticStation;
    if (automaticStation?.id == stationId) return automaticStation;

    return Station(
      id: stationId,
      name: selected?.stationName ?? selected?.primaryLabel ?? stationId,
      river: selected?.riverName ?? selected?.waterName ?? '',
      level: double.nan,
      trend: WaterTrend.stable,
      latitude: latitude,
      longitude: longitude,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      hasWaterLevel: false,
      hasKnownTrend: false,
      waterLevelSource: selected?.source ?? 'Selected context',
    );
  }

  void _open(FluviUtilityDefinition utility) {
    if (const <String>{
      'map.access',
      'journal.bite-effort',
      'safety.ready-to-fish',
      'safety.check-in',
      'fluvi.vision',
    }.contains(utility.id)) {
      unawaited(_showUnavailable(utility));
      return;
    }
    if (utility.id == 'catches.add') {
      unawaited(AppNavigator.open<bool>(context, AppDestination.addCatch));
      return;
    }
    if (utility.id == 'water.hydro-pulse') {
      unawaited(_openHydroRomania());
      return;
    }
    if (utility.destination == AppDestination.home) {
      widget.onSelectMainTab(0);
      return;
    }

    final station = _stationArgument(ref.read(selectedContextProvider));
    if (utility.destination == AppDestination.map && station == null) {
      widget.onSelectMainTab(1);
      return;
    }
    final carriesStation =
        utility.destination == AppDestination.map ||
        utility.destination == AppDestination.water ||
        utility.destination == AppDestination.weather ||
        utility.destination == AppDestination.fluvi;
    unawaited(
      AppNavigator.open<void>(
        context,
        utility.destination,
        arguments: carriesStation ? station : null,
        dataSource: widget.dataSource,
      ),
    );
  }

  Future<void> _openHydroRomania() async {
    if (ref.read(fluviAccessTierProvider) != FluviAccessTier.premium) {
      await AppNavigator.open<void>(context, AppDestination.premium);
      return;
    }

    await ref
        .read(contentRegionProvider.notifier)
        .selectCountry(countryCode: 'RO', region: 'România');
    if (!mounted) return;

    await AppNavigator.open<void>(
      context,
      AppDestination.map,
      arguments: const RuntimeMapCameraTarget(
        source: 'hydro-ro-utility',
        entityId: 'country-pack-ro',
        latitude: 45.9432,
        longitude: 24.9668,
        zoom: 5.65,
      ),
    );
  }

  Future<void> _showUnavailable(FluviUtilityDefinition utility) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(utility.title(isRomanian)),
        content: Text(context.l10n.exploreUnavailableMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  String _sectionTitle(BuildContext context, FluviExploreSection section) =>
      switch (section) {
        FluviExploreSection.conditionsAndWater =>
          context.l10n.exploreConditionsAndWater,
        FluviExploreSection.fluviIntelligence =>
          context.l10n.exploreFluviIntelligence,
        FluviExploreSection.activity => context.l10n.exploreActivity,
        FluviExploreSection.saved => context.l10n.exploreSaved,
        FluviExploreSection.rulesAndSafety =>
          context.l10n.exploreRulesAndSafety,
        FluviExploreSection.accountAndApp => context.l10n.exploreAccountAndApp,
      };

  IconData _sectionIcon(FluviExploreSection section) => switch (section) {
    FluviExploreSection.conditionsAndWater => Icons.water_rounded,
    FluviExploreSection.fluviIntelligence => Icons.auto_awesome_rounded,
    FluviExploreSection.activity => Icons.timeline_rounded,
    FluviExploreSection.saved => Icons.bookmark_rounded,
    FluviExploreSection.rulesAndSafety => Icons.health_and_safety_rounded,
    FluviExploreSection.accountAndApp => Icons.tune_rounded,
  };

  Color _sectionAccent(BuildContext context, FluviExploreSection section) =>
      switch (section) {
        FluviExploreSection.conditionsAndWater =>
          FluviAICommercialTokens.brandFocus,
        FluviExploreSection.fluviIntelligence =>
          FluviAICommercialTokens.premium,
        FluviExploreSection.activity => FluviAICommercialTokens.waterStable,
        FluviExploreSection.saved => const Color(0xFF67B8FF),
        FluviExploreSection.rulesAndSafety => FluviAICommercialTokens.warning,
        FluviExploreSection.accountAndApp => FluviAIThemeColors.of(
          context,
        ).textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final accessTier = ref.watch(fluviAccessTierProvider);
    final grouped = FluviExploreCatalog.grouped(
      FluviUtilityRegistry.definitions,
    );
    final searchResults = _query.trim().isEmpty
        ? const <FluviUtilityDefinition>[]
        : FluviUtilityRegistry.search(_query, isRomanian: isRomanian);
    final visibleSections = _selectedSection == null
        ? FluviExploreCatalog.sectionOrder
        : <FluviExploreSection>[_selectedSection!];

    return Material(
      key: const ValueKey('utilities-hub-page'),
      color: FluviAIThemeColors.of(context).background,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey<String>('utilities-hub-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _ExploreHeader(
                  title: context.l10n.exploreTitle,
                  subtitle: context.l10n.exploreSubtitle,
                  notificationTooltip: context.l10n.notifications,
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
                child: _ExploreSearchBar(
                  controller: _searchController,
                  hint: context.l10n.exploreSearchHint,
                  query: _query,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  key: const ValueKey('utilities-category-strip'),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  scrollDirection: Axis.horizontal,
                  itemCount: FluviExploreCatalog.sectionOrder.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, index) {
                    final section = index == 0
                        ? null
                        : FluviExploreCatalog.sectionOrder[index - 1];
                    return _ExploreFilterChip(
                      key: ValueKey(
                        section == null
                            ? 'utilities-filter-all'
                            : 'utilities-filter-${section.name}',
                      ),
                      label: section == null
                          ? context.l10n.exploreAll
                          : _sectionTitle(context, section),
                      icon: section == null
                          ? Icons.apps_rounded
                          : _sectionIcon(section),
                      selected: _selectedSection == section,
                      onTap: () => setState(() => _selectedSection = section),
                    );
                  },
                ),
              ),
            ),
            if (_query.trim().isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _ExploreSectionHeader(
                    title: context.l10n.exploreResults,
                    count: searchResults.length,
                    icon: Icons.search_rounded,
                    accent: FluviAICommercialTokens.brandFocus,
                  ),
                ),
              ),
              if (searchResults.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: _ExploreEmpty(
                      title: context.l10n.exploreNoResultsTitle,
                      message: context.l10n.exploreNoResultsMessage,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: searchResults.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) => _ExploreResultTile(
                      utility: searchResults[index],
                      isRomanian: isRomanian,
                      showPremium:
                          accessTier != FluviAccessTier.premium &&
                          searchResults[index].entitlement !=
                              FluviEntitlementPolicy.free,
                      onTap: () => _open(searchResults[index]),
                    ),
                  ),
                ),
            ] else
              SliverList.builder(
                itemCount: visibleSections.length,
                itemBuilder: (context, index) {
                  final section = visibleSections[index];
                  final definitions = grouped[section]!;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      index == 0 ? 14 : 20,
                      16,
                      0,
                    ),
                    child: _ExploreSectionBlock(
                      sectionKey: section.name,
                      title: _sectionTitle(context, section),
                      icon: _sectionIcon(section),
                      accent: _sectionAccent(context, section),
                      definitions: definitions,
                      isRomanian: isRomanian,
                      accessTier: accessTier,
                      onOpen: _open,
                    ),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 92)),
          ],
        ),
      ),
    );
  }
}

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader({
    required this.title,
    required this.subtitle,
    required this.notificationTooltip,
    required this.onNotifications,
  });

  final String title;
  final String subtitle;
  final String notificationTooltip;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 19,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: notificationTooltip,
          child: SizedBox.square(
            dimension: 44,
            child: Material(
              key: const ValueKey('utilities-notifications-action'),
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onNotifications,
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: colors.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExploreSearchBar extends StatelessWidget {
  const _ExploreSearchBar({
    required this.controller,
    required this.hint,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: BorderSide(color: colors.border),
    );

    return Material(
      key: const ValueKey('utilities-search-surface'),
      color: colors.surfaceRaised,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 46,
        child: TextField(
          key: const ValueKey('utilities-search-field'),
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(color: colors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            filled: false,
            fillColor: Colors.transparent,
            prefixIcon: Icon(
              Icons.search_rounded,
              color: colors.textSecondary,
              size: 21,
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).deleteButtonTooltip,
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _ExploreFilterChip extends StatelessWidget {
  const _ExploreFilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final selectedForeground = Theme.of(context).brightness == Brightness.dark
        ? FluviAICommercialTokens.brandFocus
        : FluviAICommercialTokens.accentDeep;
    return Material(
      color: selected
          ? FluviAICommercialTokens.brandFocus.withValues(alpha: .16)
          : colors.surfaceRaised,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? FluviAICommercialTokens.brandFocus.withValues(alpha: .55)
                  : colors.borderSoft,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? selectedForeground : colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? selectedForeground : colors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreSectionBlock extends StatelessWidget {
  const _ExploreSectionBlock({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.accent,
    required this.definitions,
    required this.isRomanian,
    required this.accessTier,
    required this.onOpen,
  });

  final String sectionKey;
  final String title;
  final IconData icon;
  final Color accent;
  final List<FluviUtilityDefinition> definitions;
  final bool isRomanian;
  final FluviAccessTier accessTier;
  final ValueChanged<FluviUtilityDefinition> onOpen;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final columns = largeText ? 1 : 2;
    final rows = (definitions.length / columns).ceil();
    final extent = largeText ? 82.0 : 68.0;
    return Column(
      key: ValueKey('utilities-section-$sectionKey'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExploreSectionHeader(
          title: title,
          count: definitions.length,
          icon: icon,
          accent: accent,
        ),
        const SizedBox(height: 9),
        SizedBox(
          height: rows * extent + (rows - 1) * 7,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 7,
              mainAxisSpacing: 7,
              mainAxisExtent: extent,
            ),
            itemCount: definitions.length,
            itemBuilder: (context, index) {
              final utility = definitions[index];
              return _CompactUtilityTile(
                utility: utility,
                isRomanian: isRomanian,
                accent: accent,
                showPremium:
                    accessTier != FluviAccessTier.premium &&
                    utility.entitlement != FluviEntitlementPolicy.free,
                onTap: () => onOpen(utility),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExploreSectionHeader extends StatelessWidget {
  const _ExploreSectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.accent,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accent, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: colors.textMuted,
              fontFamily: FluviAICommercialTokens.monoFontFamily,
              fontSize: 9,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactUtilityTile extends StatelessWidget {
  const _CompactUtilityTile({
    required this.utility,
    required this.isRomanian,
    required this.accent,
    required this.showPremium,
    required this.onTap,
  });

  final FluviUtilityDefinition utility;
  final bool isRomanian;
  final Color accent;
  final bool showPremium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Material(
      key: ValueKey('utility-${utility.id}'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.borderSoft),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(utility.icon, color: accent, size: 18),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    utility.title(isRomanian),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 10.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showPremium)
                  const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Text(
                      'PRO',
                      style: TextStyle(
                        color: FluviAICommercialTokens.premium,
                        fontFamily: FluviAICommercialTokens.monoFontFamily,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreResultTile extends StatelessWidget {
  const _ExploreResultTile({
    required this.utility,
    required this.isRomanian,
    required this.showPremium,
    required this.onTap,
  });

  final FluviUtilityDefinition utility;
  final bool isRomanian;
  final bool showPremium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Material(
      key: ValueKey('utility-search-${utility.id}'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.borderSoft),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  utility.icon,
                  color: FluviAICommercialTokens.brandFocus,
                  size: 20,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              utility.title(isRomanian),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (showPremium)
                            const Text(
                              'PRO',
                              style: TextStyle(
                                color: FluviAICommercialTokens.premium,
                                fontFamily:
                                    FluviAICommercialTokens.monoFontFamily,
                                fontSize: 8,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        utility.subtitle(isRomanian),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreEmpty extends StatelessWidget {
  const _ExploreEmpty({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: colors.textMuted, size: 28),
          const SizedBox(height: 9),
          Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
