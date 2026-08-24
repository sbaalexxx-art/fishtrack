import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/current_location.dart';
import '../../../core/context/selected_context.dart';
import '../../../core/map/pending_map_camera.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/water_entry.dart';
import '../../../core/theme/fluviai_commercial_tokens.dart';
import '../../../core/utility/fluviai_explore_catalog.dart';
import '../../../core/utility/fluviai_utility_registry.dart';
import '../../../features/commercial_home/data/commercial_home_data_source.dart';
import '../../../screens/weather_page.dart';

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
  String _query = '';
  FluviExploreSection? _expandedSection =
      FluviExploreCatalog.sectionOrder.first;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(FluviUtilityDefinition utility) {
    if (utility.id == 'water.hydro-pulse') {
      unawaited(_openHydroRomania());
      return;
    }
    if (utility.id == 'water.stations') {
      unawaited(
        AppNavigator.open<void>(
          context,
          AppDestination.water,
          arguments: const WaterHubRequest(
            initialSection: WaterHubSection.danube,
          ),
          dataSource: widget.dataSource,
        ),
      );
      return;
    }
    if (utility.id == 'weather.solunar') {
      unawaited(
        AppNavigator.open<void>(
          context,
          AppDestination.weather,
          arguments: WeatherPageSection.solunar,
          dataSource: widget.dataSource,
        ),
      );
      return;
    }
    unawaited(
      AppNavigator.open<void>(
        context,
        utility.destination,
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

  String _sectionTitle(bool isRomanian, FluviExploreSection section) =>
      switch (section) {
        FluviExploreSection.waterTools =>
          isRomanian ? 'Apă & hidrologie' : 'Water & hydrology',
        FluviExploreSection.weatherAndLight =>
          isRomanian ? 'Vreme & lumină' : 'Weather & light',
        FluviExploreSection.discoveryAndAssistance =>
          isRomanian ? 'Căutare & asistență' : 'Search & assistance',
      };

  IconData _sectionIcon(FluviExploreSection section) => switch (section) {
    FluviExploreSection.waterTools => Icons.water_outlined,
    FluviExploreSection.weatherAndLight => Icons.wb_twilight_outlined,
    FluviExploreSection.discoveryAndAssistance => Icons.travel_explore_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final accessTier = ref.watch(fluviAccessTierProvider);
    final colors = FluviAIThemeColors.of(context);
    final grouped = FluviExploreCatalog.grouped(
      FluviExploreCatalog.visibleDefinitions,
    );
    final searchResults = FluviExploreCatalog.searchVisible(
      _query,
      isRomanian: isRomanian,
    );
    final searching = _query.trim().isNotEmpty;

    return Material(
      key: const ValueKey('utilities-hub-page'),
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey<String>('utilities-hub-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _UtilitiesHeader(isRomanian: isRomanian),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              sliver: SliverToBoxAdapter(
                child: _UtilitiesSearch(
                  controller: _searchController,
                  query: _query,
                  hint: isRomanian
                      ? 'Caută o unealtă...'
                      : 'Search for a tool...',
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
              ),
            ),
            if (searching)
              if (searchResults.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptySearch(isRomanian: isRomanian),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList.separated(
                    itemCount: searchResults.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.borderSoft),
                    itemBuilder: (context, index) => _ToolRow(
                      key: ValueKey(
                        'utility-search-${searchResults[index].id}',
                      ),
                      utility: searchResults[index],
                      isRomanian: isRomanian,
                      showPremium:
                          accessTier != FluviAccessTier.premium &&
                          searchResults[index].entitlement !=
                              FluviEntitlementPolicy.free,
                      onTap: () => _open(searchResults[index]),
                    ),
                  ),
                )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: FluviExploreCatalog.sectionOrder.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: colors.borderSoft),
                  itemBuilder: (context, index) {
                    final section = FluviExploreCatalog.sectionOrder[index];
                    final definitions = grouped[section]!;
                    final expanded = _expandedSection == section;
                    return _ToolSection(
                      sectionKey: section.name,
                      title: _sectionTitle(isRomanian, section),
                      icon: _sectionIcon(section),
                      definitions: definitions,
                      expanded: expanded,
                      isRomanian: isRomanian,
                      accessTier: accessTier,
                      onToggle: () => setState(() {
                        _expandedSection = expanded ? null : section;
                      }),
                      onOpen: _open,
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _UtilitiesHeader extends StatelessWidget {
  const _UtilitiesHeader({required this.isRomanian});

  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isRomanian ? 'Instrumente' : 'Tools',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          isRomanian
              ? 'Unelte distincte, fără scurtături duplicate.'
              : 'Distinct tools without duplicate launchers.',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _UtilitiesSearch extends StatelessWidget {
  const _UtilitiesSearch({
    required this.controller,
    required this.query,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Container(
      key: const ValueKey('utilities-search-surface'),
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: colors.backgroundRaised,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        key: const ValueKey('utilities-search-field'),
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
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
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          hintText: hint,
          hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({
    required this.sectionKey,
    required this.title,
    required this.icon,
    required this.definitions,
    required this.expanded,
    required this.isRomanian,
    required this.accessTier,
    required this.onToggle,
    required this.onOpen,
  });

  final String sectionKey;
  final String title;
  final IconData icon;
  final List<FluviUtilityDefinition> definitions;
  final bool expanded;
  final bool isRomanian;
  final FluviAccessTier accessTier;
  final VoidCallback onToggle;
  final ValueChanged<FluviUtilityDefinition> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      key: ValueKey('utilities-section-$sectionKey'),
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          child: InkWell(
            key: ValueKey('utilities-section-toggle-$sectionKey'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: expanded ? accent : colors.textSecondary,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    definitions.length.toString(),
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: colors.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          for (var index = 0; index < definitions.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Divider(height: 1, color: colors.borderSoft),
              ),
            _ToolRow(
              key: ValueKey('utility-${definitions[index].id}'),
              utility: definitions[index],
              isRomanian: isRomanian,
              showPremium:
                  accessTier != FluviAccessTier.premium &&
                  definitions[index].entitlement != FluviEntitlementPolicy.free,
              onTap: () => onOpen(definitions[index]),
            ),
          ],
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    super.key,
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
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      label: utility.title(isRomanian),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                Icon(utility.icon, color: accent, size: 20),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        utility.title(isRomanian),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        utility.subtitle(isRomanian),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showPremium) ...[
                  const SizedBox(width: 8),
                  Text(
                    'PRO',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.isRomanian});

  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: colors.textMuted, size: 30),
            const SizedBox(height: 10),
            Text(
              isRomanian ? 'Nicio unealtă găsită' : 'No tool found',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isRomanian
                  ? 'Caută în instrumentele distincte disponibile.'
                  : 'Search the distinct tools currently available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
