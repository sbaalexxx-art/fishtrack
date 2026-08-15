import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/home_premium/home_header.dart';
import '../widgets/home_premium/home_premium_layout.dart';
import 'home_design_lab_tokens.dart';

enum HomeDesignLabTier { free, premium }

@immutable
class _HomePreviewConfiguration {
  const _HomePreviewConfiguration._({
    required this.tier,
    required this.showsPremiumAccent,
    required this.canViewAllWaterCategories,
    required this.canUseWaterActions,
    required this.showsWaterTelemetry,
    required this.showsFluviInsight,
    required this.showsCommunityInsight,
  });

  factory _HomePreviewConfiguration.fromTier(HomeDesignLabTier tier) {
    return switch (tier) {
      HomeDesignLabTier.free => const _HomePreviewConfiguration._(
        tier: HomeDesignLabTier.free,
        showsPremiumAccent: false,
        canViewAllWaterCategories: false,
        canUseWaterActions: false,
        showsWaterTelemetry: false,
        showsFluviInsight: false,
        showsCommunityInsight: false,
      ),
      HomeDesignLabTier.premium => const _HomePreviewConfiguration._(
        tier: HomeDesignLabTier.premium,
        showsPremiumAccent: true,
        canViewAllWaterCategories: true,
        canUseWaterActions: true,
        showsWaterTelemetry: true,
        showsFluviInsight: true,
        showsCommunityInsight: true,
      ),
    };
  }

  final HomeDesignLabTier tier;
  final bool showsPremiumAccent;
  final bool canViewAllWaterCategories;
  final bool canUseWaterActions;
  final bool showsWaterTelemetry;
  final bool showsFluviInsight;
  final bool showsCommunityInsight;
}

@immutable
class _LabCopy {
  const _LabCopy._(this.isRomanian);

  factory _LabCopy.of(BuildContext context) {
    return _LabCopy._(
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ro',
    );
  }

  final bool isRomanian;

  String text({required String ro, required String en}) {
    return isRomanian ? ro : en;
  }
}

class HomeDesignLabPage extends StatefulWidget {
  const HomeDesignLabPage({
    super.key,
    this.initialTier = HomeDesignLabTier.free,
  });

  final HomeDesignLabTier initialTier;

  @override
  State<HomeDesignLabPage> createState() => _HomeDesignLabPageState();
}

class _HomeDesignLabPageState extends State<HomeDesignLabPage> {
  late HomeDesignLabTier _tier;

  @override
  void initState() {
    super.initState();
    _tier = widget.initialTier;
  }

  void _selectTier(HomeDesignLabTier tier) {
    if (_tier == tier) return;
    setState(() => _tier = tier);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const _DesignLabBottomNavigation(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = HomePremiumLayout.fromViewport(
              context,
              viewportSize: constraints.biggest,
              systemSafeArea: MediaQuery.viewPaddingOf(context),
            );
            final configuration = _HomePreviewConfiguration.fromTier(_tier);
            return layout.isLandscape
                ? _LandscapeHome(
                    layout: layout,
                    configuration: configuration,
                    onTierSelected: _selectTier,
                  )
                : _PortraitHome(
                    layout: layout,
                    configuration: configuration,
                    onTierSelected: _selectTier,
                  );
          },
        ),
      ),
    );
  }
}

class _PortraitHome extends StatelessWidget {
  const _PortraitHome({
    required this.layout,
    required this.configuration,
    required this.onTierSelected,
  });

  final HomePremiumLayout layout;
  final _HomePreviewConfiguration configuration;
  final ValueChanged<HomeDesignLabTier> onTierSelected;

  @override
  Widget build(BuildContext context) {
    final mapHeight = math
        .max(240, layout.usableHeight * .40)
        .clamp(0, layout.heroMapHeight)
        .toDouble();

    return SingleChildScrollView(
      key: const Key('home-design-lab-portrait-scroll'),
      padding: const EdgeInsets.only(bottom: HomeDesignLabTokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabHeader(configuration: configuration, layout: layout),
          const Center(child: _LocationChip()),
          const SizedBox(height: HomeDesignLabTokens.locationMapGap),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: HomeDesignLabTokens.space12,
            ),
            child: SizedBox(
              height: mapHeight,
              child: _LocalMapPreview(
                key: const Key('home-design-lab-map'),
                tier: configuration.tier,
                onTierSelected: onTierSelected,
              ),
            ),
          ),
          SizedBox(height: math.min(layout.sectionGap, 6)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.horizontalPadding),
            child: _HomeContent(
              configuration: configuration,
              layout: layout,
              includeBottomClearance: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandscapeHome extends StatelessWidget {
  const _LandscapeHome({
    required this.layout,
    required this.configuration,
    required this.onTierSelected,
  });

  final HomePremiumLayout layout;
  final _HomePreviewConfiguration configuration;
  final ValueChanged<HomeDesignLabTier> onTierSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LabHeader(configuration: configuration, layout: layout),
        const Center(child: _LocationChip()),
        const SizedBox(height: HomeDesignLabTokens.locationMapGap),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              HomeDesignLabTokens.space12,
              0,
              HomeDesignLabTokens.space12,
              HomeDesignLabTokens.space12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: _LocalMapPreview(
                    key: const Key('home-design-lab-map'),
                    tier: configuration.tier,
                    onTierSelected: onTierSelected,
                  ),
                ),
                const SizedBox(width: HomeDesignLabTokens.space12),
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(
                    key: const Key('home-design-lab-landscape-scroll'),
                    child: _HomeContent(
                      configuration: configuration,
                      layout: layout,
                      includeBottomClearance: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabHeader extends StatelessWidget {
  const _LabHeader({required this.configuration, required this.layout});

  final _HomePreviewConfiguration configuration;
  final HomePremiumLayout layout;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: math.min(layout.headerHeight, layout.isTablet ? 76 : 46),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: HomeDesignLabTokens.space12,
          vertical: HomeDesignLabTokens.space2,
        ),
        child: Row(
          children: [
            const Expanded(
              child: HomePremiumHeader(
                key: Key('home-design-lab-header'),
                notificationCount: 3,
              ),
            ),
            const SizedBox(width: HomeDesignLabTokens.space8),
            Semantics(
              label: configuration.showsPremiumAccent
                  ? copy.text(
                      ro: 'Avatar profil Premium',
                      en: 'Premium profile avatar',
                    )
                  : copy.text(
                      ro: 'Avatar profil Free',
                      en: 'Free profile avatar',
                    ),
              button: true,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HomeDesignLabTokens.surfaceElevated,
                  border: Border.all(
                    color: configuration.showsPremiumAccent
                        ? HomeDesignLabTokens.premiumGold
                        : HomeDesignLabTokens.border,
                    width: configuration.showsPremiumAccent ? 1.4 : 1,
                  ),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: HomeDesignLabTokens.primaryText,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip();

  @override
  Widget build(BuildContext context) {
    final availableWidth = math
        .max(
          0,
          MediaQuery.sizeOf(context).width - (HomeDesignLabTokens.space12 * 2),
        )
        .toDouble();
    return Semantics(
      label: 'Patchway, South Gloucestershire',
      child: Container(
        key: const Key('home-design-lab-location-chip'),
        constraints: BoxConstraints(
          maxWidth: math.min(260, availableWidth),
          minHeight: 28,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: HomeDesignLabTokens.space10,
          vertical: HomeDesignLabTokens.space4,
        ),
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.surface,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
          border: Border.all(color: HomeDesignLabTokens.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_on_rounded,
              color: HomeDesignLabTokens.cyanAccent,
              size: 13,
            ),
            SizedBox(width: HomeDesignLabTokens.space4),
            Flexible(
              child: Text(
                'Patchway, South Gloucestershire',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: HomeDesignLabTokens.secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierPill extends StatelessWidget {
  const _TierPill({required this.tier, required this.onTierSelected});

  final HomeDesignLabTier tier;
  final ValueChanged<HomeDesignLabTier> onTierSelected;

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<HomeDesignLabTier>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: HomeDesignLabTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HomeDesignLabTokens.radius20),
        ),
      ),
      builder: (context) => _TierPickerSheet(tier: tier),
    );
    if (selected != null && context.mounted) {
      onTierSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = tier == HomeDesignLabTier.premium;
    final label = premium ? 'PREMIUM' : 'FREE';
    return Semantics(
      button: true,
      label: 'Design Lab tier: $label',
      child: Material(
        key: const Key('home-design-lab-tier-pill'),
        color: HomeDesignLabTokens.scrim,
        borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
        child: InkWell(
          onTap: () => _openPicker(context),
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
          child: Container(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 32),
            padding: const EdgeInsets.symmetric(
              horizontal: HomeDesignLabTokens.space8,
              vertical: HomeDesignLabTokens.space4,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                HomeDesignLabTokens.radiusPill,
              ),
              border: Border.all(
                color: premium
                    ? HomeDesignLabTokens.premiumGold
                    : HomeDesignLabTokens.cyanAccent,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: premium
                    ? HomeDesignLabTokens.premiumGold
                    : HomeDesignLabTokens.cyanAccent,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TierPickerSheet extends StatelessWidget {
  const _TierPickerSheet({required this.tier});

  final HomeDesignLabTier tier;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Padding(
      key: const Key('home-design-lab-tier-picker'),
      padding: const EdgeInsets.fromLTRB(
        HomeDesignLabTokens.space16,
        HomeDesignLabTokens.space10,
        HomeDesignLabTokens.space16,
        HomeDesignLabTokens.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: HomeDesignLabTokens.border,
                borderRadius: BorderRadius.circular(
                  HomeDesignLabTokens.radiusPill,
                ),
              ),
            ),
          ),
          const SizedBox(height: HomeDesignLabTokens.space12),
          Text(
            copy.text(ro: 'Preview Design Lab', en: 'Design Lab preview'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HomeDesignLabTokens.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: HomeDesignLabTokens.space4),
          Text(
            copy.text(
              ro: 'Alege varianta vizuală. Nu schimbă abonamentul.',
              en: 'Choose a visual variant. This does not change a subscription.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HomeDesignLabTokens.secondaryText,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: HomeDesignLabTokens.space12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: _TierButton(
                    key: const Key('home-design-lab-tier-free'),
                    label: 'Free',
                    selected: tier == HomeDesignLabTier.free,
                    onTap: () =>
                        Navigator.of(context).pop(HomeDesignLabTier.free),
                  ),
                ),
              ),
              const SizedBox(width: HomeDesignLabTokens.space8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: _TierButton(
                    key: const Key('home-design-lab-tier-premium'),
                    label: 'Premium',
                    selected: tier == HomeDesignLabTier.premium,
                    premium: true,
                    onTap: () =>
                        Navigator.of(context).pop(HomeDesignLabTier.premium),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierButton extends StatelessWidget {
  const _TierButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.premium = false,
  });

  final String label;
  final bool selected;
  final bool premium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: copy.text(ro: 'Previzualizare $label', en: '$label preview'),
      child: Material(
        color: selected
            ? HomeDesignLabTokens.surfaceElevated
            : HomeDesignLabTokens.background,
        borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected && premium
                    ? HomeDesignLabTokens.premiumGold
                    : HomeDesignLabTokens.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesignLabBottomNavigation extends StatelessWidget {
  const _DesignLabBottomNavigation();

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final copy = _LabCopy.of(context);
    final navigationHeight = (layout.bottomNavHeight * .86)
        .clamp(50, 58)
        .toDouble();
    return SafeArea(
      top: false,
      minimum: EdgeInsets.symmetric(horizontal: layout.horizontalPadding * .50),
      child: Container(
        key: const Key('home-design-lab-bottom-navigation'),
        height: navigationHeight,
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.surface,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius20),
          border: Border.all(color: HomeDesignLabTokens.border),
          boxShadow: const [
            BoxShadow(
              color: HomeDesignLabTokens.shadow,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _BottomNavigationItem(
              key: const Key('home-design-lab-nav-home'),
              icon: Icons.home_rounded,
              label: copy.text(ro: 'Acasă', en: 'Home'),
              selected: true,
            ),
            _BottomNavigationItem(
              key: const Key('home-design-lab-nav-map'),
              icon: Icons.map_rounded,
              label: copy.text(ro: 'Hartă', en: 'Map'),
            ),
            _BottomAddAction(navigationHeight: navigationHeight),
            _BottomNavigationItem(
              key: const Key('home-design-lab-nav-reports'),
              icon: Icons.bar_chart_rounded,
              label: copy.text(ro: 'Rapoarte', en: 'Reports'),
            ),
            _BottomNavigationItem(
              key: const Key('home-design-lab-nav-favorites'),
              icon: Icons.bookmark_rounded,
              label: copy.text(ro: 'Favorite', en: 'Favorites'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavigationItem extends StatelessWidget {
  const _BottomNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final color = selected
        ? HomeDesignLabTokens.cyanAccent
        : HomeDesignLabTokens.secondaryText;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 22,
                decoration: BoxDecoration(
                  color: selected
                      ? HomeDesignLabTokens.subtleCyan
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    HomeDesignLabTokens.radiusPill,
                  ),
                ),
                child: Icon(icon, color: color, size: 20 * layout.iconScale),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                  color: color,
                  fontSize: 9 * layout.bodyFontScale,
                  height: 1,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomAddAction extends StatelessWidget {
  const _BottomAddAction({required this.navigationHeight});

  final double navigationHeight;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    final size = (navigationHeight - 8).clamp(40, 48).toDouble();
    return Expanded(
      child: Semantics(
        button: true,
        label: copy.text(ro: 'Adaugă captură', en: 'Add catch'),
        child: Center(
          child: InkWell(
            key: const Key('home-design-lab-nav-add'),
            onTap: () {},
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: HomeDesignLabTokens.cyanAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: HomeDesignLabTokens.subtleCyan,
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add,
                color: HomeDesignLabTokens.background,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.configuration,
    required this.layout,
    required this.includeBottomClearance,
  });

  final _HomePreviewConfiguration configuration;
  final HomePremiumLayout layout;
  final bool includeBottomClearance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WaterCard(configuration: configuration),
        SizedBox(height: layout.sectionGap),
        const _WeatherCard(),
        SizedBox(height: layout.sectionGap),
        _ScoreAndCommunity(configuration: configuration),
        SizedBox(height: layout.sectionGap),
        const _RecentCatches(),
        if (includeBottomClearance)
          SizedBox(
            height: math.max(
              HomeDesignLabTokens.space24,
              layout.bottomContentClearance,
            ),
          ),
      ],
    );
  }
}

class _LocalMapPreview extends StatelessWidget {
  const _LocalMapPreview({
    super.key,
    required this.tier,
    required this.onTierSelected,
  });

  final HomeDesignLabTier tier;
  final ValueChanged<HomeDesignLabTier> onTierSelected;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Semantics(
      label: copy.text(
        ro: 'Hartă locală demonstrativă. Date de design, fără informații reale.',
        en: 'Local demonstration map. Design data, no real information.',
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: HomeDesignLabTokens.mapBackground,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const CustomPaint(painter: _MapPreviewPainter()),
              const Positioned(
                left: 12,
                top: 12,
                right: 68,
                child: _MapSearch(),
              ),
              Positioned(
                left: 12,
                top: 62,
                child: _TierPill(tier: tier, onTierSelected: onTierSelected),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Column(
                  children: [
                    _MapAction(
                      label: copy.text(ro: 'Straturi hartă', en: 'Map layers'),
                      icon: Icons.layers_outlined,
                    ),
                    const SizedBox(height: HomeDesignLabTokens.space8),
                    _MapAction(
                      label: copy.text(ro: 'Locația mea', en: 'My location'),
                      icon: Icons.my_location_rounded,
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 84,
                top: 96,
                child: _MapPin(color: HomeDesignLabTokens.waterRising),
              ),
              const Positioned(
                right: 92,
                top: 126,
                child: _MapPin(color: HomeDesignLabTokens.waterStable),
              ),
              const Positioned(
                left: 126,
                bottom: 82,
                child: _MapPin(color: HomeDesignLabTokens.waterFalling),
              ),
              const Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _MapFooter(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapSearch extends StatelessWidget {
  const _MapSearch();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Semantics(
      button: true,
      label: copy.text(
        ro: 'Caută pe harta demonstrativă',
        en: 'Search the demonstration map',
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 210),
        height: 42,
        padding: const EdgeInsets.symmetric(
          horizontal: HomeDesignLabTokens.space12,
        ),
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.scrim,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius12),
          border: Border.all(color: HomeDesignLabTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_rounded,
              size: 18,
              color: HomeDesignLabTokens.primaryText,
            ),
            const SizedBox(width: HomeDesignLabTokens.space8),
            Flexible(
              child: Text(
                copy.text(ro: 'Caută zonă', en: 'Search area'),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomeDesignLabTokens.secondaryText,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapAction extends StatelessWidget {
  const _MapAction({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.scrim,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius12),
          border: Border.all(color: HomeDesignLabTokens.border),
        ),
        child: Icon(icon, size: 19, color: HomeDesignLabTokens.primaryText),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.location_on_rounded, color: color, size: 29);
  }
}

class _MapFooter extends StatelessWidget {
  const _MapFooter();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: HomeDesignLabTokens.space6,
          runSpacing: HomeDesignLabTokens.space4,
          children: [
            const _StatusBadge(
              label: 'LIVE',
              color: HomeDesignLabTokens.waterStable,
            ),
            const _StatusBadge(
              label: 'PREVIEW',
              color: HomeDesignLabTokens.cyanAccent,
            ),
          ],
        ),
        const SizedBox(height: HomeDesignLabTokens.space6),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: HomeDesignLabTokens.space8,
            vertical: HomeDesignLabTokens.space6,
          ),
          decoration: BoxDecoration(
            color: HomeDesignLabTokens.scrim,
            borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
          ),
          child: Wrap(
            spacing: HomeDesignLabTokens.space10,
            runSpacing: HomeDesignLabTokens.space4,
            children: [
              _LegendItem(
                color: HomeDesignLabTokens.waterRising,
                label: copy.text(ro: 'crește', en: 'rising'),
              ),
              _LegendItem(
                color: HomeDesignLabTokens.waterStable,
                label: copy.text(ro: 'stabil', en: 'stable'),
              ),
              _LegendItem(
                color: HomeDesignLabTokens.waterFalling,
                label: copy.text(ro: 'scade', en: 'falling'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HomeDesignLabTokens.space8,
        vertical: HomeDesignLabTokens.space4,
      ),
      decoration: BoxDecoration(
        color: HomeDesignLabTokens.scrim,
        borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: HomeDesignLabTokens.space4),
        Text(
          label,
          style: const TextStyle(
            color: HomeDesignLabTokens.secondaryText,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.configuration});

  final _HomePreviewConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return _LabCard(
      key: const Key('home-design-lab-water-card'),
      padding: 9,
      semanticLabel: copy.text(
        ro: 'Date demonstrative locale pentru apă',
        en: 'Local demonstration water data',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            icon: Icons.water_rounded,
            title: 'Water',
            trailing: configuration.showsPremiumAccent
                ? const _PremiumIndicator()
                : const _LocalDataLabel(),
          ),
          const SizedBox(height: HomeDesignLabTokens.space6),
          Wrap(
            spacing: HomeDesignLabTokens.space6,
            runSpacing: HomeDesignLabTokens.space6,
            children: [
              _SelectorChip(
                label: copy.text(ro: 'Dunăre', en: 'Danube'),
                selected: true,
              ),
              _SelectorChip(
                label: copy.text(ro: 'Râuri', en: 'Rivers'),
                locked: !configuration.canViewAllWaterCategories,
              ),
              _SelectorChip(
                label: copy.text(
                  ro: 'Baraje & acumulări',
                  en: 'Dams & reservoirs',
                ),
                locked: !configuration.canViewAllWaterCategories,
              ),
            ],
          ),
          const SizedBox(height: HomeDesignLabTokens.space10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cernavodă',
                      style: TextStyle(
                        color: HomeDesignLabTokens.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: HomeDesignLabTokens.space4),
                    Text(
                      copy.text(
                        ro: 'Stație demonstrativă',
                        en: 'Demonstration station',
                      ),
                      style: const TextStyle(
                        color: HomeDesignLabTokens.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (configuration.canUseWaterActions)
                Wrap(
                  spacing: HomeDesignLabTokens.space4,
                  children: [
                    const _CompactAction(
                      label: 'Favorite',
                      icon: Icons.star_border_rounded,
                    ),
                    _CompactAction(
                      label: copy.text(ro: 'Alertă', en: 'Alert'),
                      icon: Icons.notifications_active_outlined,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: HomeDesignLabTokens.space8),
          Wrap(
            spacing: HomeDesignLabTokens.space20,
            runSpacing: HomeDesignLabTokens.space8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: const [_PrimaryWaterValue(), _SecondaryWaterValue()],
          ),
          const SizedBox(height: HomeDesignLabTokens.space8),
          SizedBox(
            height: 42,
            child: Semantics(
              label: copy.text(
                ro: 'Mini-grafic demonstrativ cu tendință descendentă calmă',
                en: 'Demonstration mini chart with a calm falling trend',
              ),
              child: const CustomPaint(painter: _WaterChartPainter()),
            ),
          ),
          if (configuration.showsWaterTelemetry) ...[
            const SizedBox(height: HomeDesignLabTokens.space4),
            Wrap(
              spacing: HomeDesignLabTokens.space8,
              runSpacing: HomeDesignLabTokens.space6,
              children: [
                _DataPoint(
                  label: copy.text(ro: 'Debit', en: 'Flow'),
                  value: '4.180 m³/s',
                ),
                _DataPoint(
                  label: copy.text(ro: 'Temp. apă', en: 'Water temp.'),
                  value: '17,2°C',
                ),
              ],
            ),
          ],
          const SizedBox(height: HomeDesignLabTokens.space8),
          const _WaterMeta(),
          const SizedBox(height: HomeDesignLabTokens.space6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: HomeDesignLabTokens.space12,
            runSpacing: HomeDesignLabTokens.space8,
            children: [
              const _ReportsLabel(),
              _TextAction(
                label: copy.text(ro: 'Vezi detalii', en: 'View details'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimaryWaterValue extends StatelessWidget {
  const _PrimaryWaterValue();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '−12 cm / 24h',
          style: TextStyle(
            color: HomeDesignLabTokens.waterFalling,
            fontSize: 28,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: HomeDesignLabTokens.space6),
        Text(
          copy.text(ro: 'În scădere', en: 'Falling'),
          style: const TextStyle(
            color: HomeDesignLabTokens.waterFalling,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SecondaryWaterValue extends StatelessWidget {
  const _SecondaryWaterValue();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '214 cm',
          style: TextStyle(
            color: HomeDesignLabTokens.primaryText,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          copy.text(ro: 'nivel demonstrativ', en: 'demonstration level'),
          style: const TextStyle(
            color: HomeDesignLabTokens.secondaryText,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _WaterMeta extends StatelessWidget {
  const _WaterMeta();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Wrap(
      spacing: HomeDesignLabTokens.space12,
      runSpacing: HomeDesignLabTokens.space4,
      children: [
        _IconText(
          icon: Icons.storage_outlined,
          label: copy.text(ro: 'Sursa: AFDJ', en: 'Source: AFDJ'),
        ),
        _IconText(
          icon: Icons.schedule_rounded,
          label: copy.text(
            ro: 'Actualizat acum 3 ore',
            en: 'Updated 3 hours ago',
          ),
        ),
      ],
    );
  }
}

class _ReportsLabel extends StatelessWidget {
  const _ReportsLabel();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return _IconText(
      icon: Icons.forum_outlined,
      label: copy.text(ro: '3 rapoarte recente', en: '3 recent reports'),
    );
  }
}

class _SelectorChip extends StatelessWidget {
  const _SelectorChip({
    required this.label,
    this.selected = false,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: !locked,
      label: locked
          ? copy.text(
              ro: '$label, blocat în Free',
              en: '$label, locked in Free',
            )
          : label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(
          horizontal: HomeDesignLabTokens.space10,
          vertical: HomeDesignLabTokens.space8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? HomeDesignLabTokens.subtleCyan
              : HomeDesignLabTokens.background,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
          border: Border.all(
            color: selected
                ? HomeDesignLabTokens.cyanAccent
                : HomeDesignLabTokens.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked) ...[
              const Icon(
                Icons.lock_outline_rounded,
                size: 13,
                color: HomeDesignLabTokens.warning,
              ),
              const SizedBox(width: HomeDesignLabTokens.space4),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                textWidthBasis: TextWidthBasis.longestLine,
                style: TextStyle(
                  color: selected
                      ? HomeDesignLabTokens.cyanAccent
                      : HomeDesignLabTokens.secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.background,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius12),
          border: Border.all(color: HomeDesignLabTokens.border),
        ),
        child: Icon(icon, color: HomeDesignLabTokens.primaryText, size: 18),
      ),
    );
  }
}

class _DataPoint extends StatelessWidget {
  const _DataPoint({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HomeDesignLabTokens.space8,
          vertical: HomeDesignLabTokens.space4,
        ),
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.background,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius12),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: HomeDesignLabTokens.space6,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: HomeDesignLabTokens.secondaryText,
                fontSize: 8,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: HomeDesignLabTokens.primaryText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return _LabCard(
      key: const Key('home-design-lab-weather-card'),
      semanticLabel: copy.text(
        ro: 'Vreme demonstrativă locală',
        en: 'Local demonstration weather',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final narrow = constraints.maxWidth < 310 || textScale > 1.2;
          final temperature = const _WeatherTemperature();
          final details = const Expanded(child: _WeatherDetails());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle(
                icon: Icons.cloud_outlined,
                title: 'Weather',
                trailing: _LocalDataLabel(),
              ),
              const SizedBox(height: HomeDesignLabTokens.space12),
              if (narrow) ...[
                temperature,
                const SizedBox(height: HomeDesignLabTokens.space12),
                const _WeatherDetails(),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    temperature,
                    const SizedBox(width: HomeDesignLabTokens.space16),
                    details,
                  ],
                ),
              const SizedBox(height: HomeDesignLabTokens.space10),
              Align(
                alignment: Alignment.centerRight,
                child: _TextAction(
                  label: copy.text(ro: 'Detalii meteo', en: 'Weather details'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeatherTemperature extends StatelessWidget {
  const _WeatherTemperature();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '20°C',
          style: TextStyle(
            color: HomeDesignLabTokens.primaryText,
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: HomeDesignLabTokens.space6),
        Text(
          copy.text(ro: 'Parțial înnorat', en: 'Partly cloudy'),
          style: const TextStyle(
            color: HomeDesignLabTokens.secondaryText,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _WeatherDetails extends StatelessWidget {
  const _WeatherDetails();

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Wrap(
      spacing: HomeDesignLabTokens.space12,
      runSpacing: HomeDesignLabTokens.space8,
      children: [
        _IconText(
          icon: Icons.air_rounded,
          label: copy.text(ro: 'Vânt 18 km/h', en: 'Wind 18 km/h'),
        ),
        const _IconText(icon: Icons.speed_rounded, label: '1019 hPa'),
        _IconText(
          icon: Icons.water_drop_outlined,
          label: copy.text(ro: 'Ploaie 0%', en: 'Rain 0%'),
        ),
      ],
    );
  }
}

class _ScoreAndCommunity extends StatelessWidget {
  const _ScoreAndCommunity({required this.configuration});

  final _HomePreviewConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final useRow = constraints.maxWidth >= 390 && textScale <= 1.2;
        final score = _FluviScoreCard(configuration: configuration);
        final community = _CommunityCard(configuration: configuration);
        if (!useRow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              score,
              const SizedBox(height: HomeDesignLabTokens.space10),
              community,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: score),
              const SizedBox(width: HomeDesignLabTokens.space10),
              Expanded(child: community),
            ],
          ),
        );
      },
    );
  }
}

class _FluviScoreCard extends StatelessWidget {
  const _FluviScoreCard({required this.configuration});

  final _HomePreviewConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return _LabCard(
      key: const Key('home-design-lab-fluviscore-card'),
      semanticLabel: copy.text(
        ro: 'FluviScore demonstrativ',
        en: 'Demonstration FluviScore',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            icon: Icons.insights_rounded,
            title: 'FluviScore',
          ),
          const SizedBox(height: HomeDesignLabTokens.space16),
          Text(
            configuration.showsFluviInsight ? '78' : '72',
            style: const TextStyle(
              color: HomeDesignLabTokens.cyanAccent,
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: HomeDesignLabTokens.space6),
          Text(
            configuration.showsFluviInsight
                ? copy.text(
                    ro: 'Condiții favorabile',
                    en: 'Favorable conditions',
                  )
                : copy.text(ro: 'Scor de bază', en: 'Basic score'),
            style: const TextStyle(
              color: HomeDesignLabTokens.secondaryText,
              fontSize: 11,
            ),
          ),
          if (configuration.showsFluviInsight) ...[
            const SizedBox(height: HomeDesignLabTokens.space12),
            const _InsightLabel(),
            const SizedBox(height: HomeDesignLabTokens.space8),
            const Text(
              'Confidence 84%',
              style: TextStyle(
                color: HomeDesignLabTokens.primaryText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: HomeDesignLabTokens.space10),
            _TextAction(
              label: copy.text(ro: 'Analiza completă', en: 'Full analysis'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightLabel extends StatelessWidget {
  const _InsightLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 14,
          color: HomeDesignLabTokens.premiumGold,
        ),
        SizedBox(width: HomeDesignLabTokens.space4),
        Flexible(
          child: Text(
            'Fluvi Insight',
            style: TextStyle(
              color: HomeDesignLabTokens.premiumGold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.configuration});

  final _HomePreviewConfiguration configuration;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return _LabCard(
      key: const Key('home-design-lab-community-card'),
      semanticLabel: copy.text(
        ro: 'Comunitate cu date demonstrative',
        en: 'Community with demonstration data',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Icons.groups_2_outlined,
            title: copy.text(ro: 'Comunitate', en: 'Community'),
          ),
          const SizedBox(height: HomeDesignLabTokens.space16),
          Text(
            configuration.showsCommunityInsight ? '146' : '3',
            style: const TextStyle(
              color: HomeDesignLabTokens.waterStable,
              fontSize: 34,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: HomeDesignLabTokens.space6),
          Text(
            configuration.showsCommunityInsight
                ? copy.text(ro: 'observații locale', en: 'local observations')
                : copy.text(ro: 'rapoarte recente', en: 'recent reports'),
            style: const TextStyle(
              color: HomeDesignLabTokens.secondaryText,
              fontSize: 11,
            ),
          ),
          if (configuration.showsCommunityInsight) ...[
            const SizedBox(height: HomeDesignLabTokens.space12),
            Text(
              copy.text(
                ro: 'Confidence comunitate 81%',
                en: 'Community confidence 81%',
              ),
              style: const TextStyle(
                color: HomeDesignLabTokens.primaryText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: HomeDesignLabTokens.space10),
            _TextAction(
              label: copy.text(ro: 'Analiza completă', en: 'Full analysis'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentCatches extends StatelessWidget {
  const _RecentCatches();

  static const catchesRo = [
    _CatchData(
      species: 'Șalău',
      weight: '2,4 kg',
      length: '61 cm',
      time: 'acum 2h',
      privacy: 'exactă',
      icon: Icons.set_meal_rounded,
      colors: HomeDesignLabTokens.catchGradientBlue,
    ),
    _CatchData(
      species: 'Crap',
      weight: '5,8 kg',
      length: '74 cm',
      time: 'acum 4h',
      privacy: 'aprox.',
      icon: Icons.phishing_rounded,
      colors: HomeDesignLabTokens.catchGradientGreen,
    ),
    _CatchData(
      species: 'Biban',
      weight: '0,8 kg',
      length: '34 cm',
      time: 'ieri',
      privacy: 'privată',
      icon: Icons.set_meal_rounded,
      colors: HomeDesignLabTokens.catchGradientGold,
    ),
    _CatchData(
      species: 'Somn',
      weight: '9,2 kg',
      length: '112 cm',
      time: 'ieri',
      privacy: 'aprox.',
      icon: Icons.phishing_rounded,
      colors: HomeDesignLabTokens.catchGradientPurple,
    ),
    _CatchData(
      species: 'Avat',
      weight: '1,6 kg',
      length: '49 cm',
      time: '2 zile',
      privacy: 'exactă',
      icon: Icons.set_meal_rounded,
      colors: HomeDesignLabTokens.catchGradientRed,
    ),
  ];

  static const catchesEn = [
    _CatchData(
      species: 'Zander',
      weight: '2.4 kg',
      length: '61 cm',
      time: '2h ago',
      privacy: 'exact',
      icon: Icons.set_meal_rounded,
      colors: HomeDesignLabTokens.catchGradientBlue,
    ),
    _CatchData(
      species: 'Carp',
      weight: '5.8 kg',
      length: '74 cm',
      time: '4h ago',
      privacy: 'approx.',
      icon: Icons.phishing_rounded,
      colors: HomeDesignLabTokens.catchGradientGreen,
    ),
    _CatchData(
      species: 'Perch',
      weight: '0.8 kg',
      length: '34 cm',
      time: 'yesterday',
      privacy: 'private',
      icon: Icons.set_meal_rounded,
      colors: HomeDesignLabTokens.catchGradientGold,
    ),
    _CatchData(
      species: 'Catfish',
      weight: '9.2 kg',
      length: '112 cm',
      time: 'yesterday',
      privacy: 'approx.',
      icon: Icons.phishing_rounded,
      colors: HomeDesignLabTokens.catchGradientPurple,
    ),
    _CatchData(
      species: 'Asp',
      weight: '1.6 kg',
      length: '49 cm',
      time: '2 days',
      privacy: 'exact',
      icon: Icons.set_meal_rounded,
      colors: HomeDesignLabTokens.catchGradientRed,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    final catches = copy.isRomanian ? catchesRo : catchesEn;
    final scale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1, 1.3).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HomeDesignLabTokens.space4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  copy.text(ro: 'Capturi recente', en: 'Recent catches'),
                  style: const TextStyle(
                    color: HomeDesignLabTokens.primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _TextAction(
                label: copy.text(ro: 'Vezi toate', en: 'View all'),
              ),
            ],
          ),
        ),
        const SizedBox(height: HomeDesignLabTokens.space10),
        SizedBox(
          height: 190 * scale,
          child: ListView.separated(
            key: const Key('home-design-lab-catches-carousel'),
            scrollDirection: Axis.horizontal,
            itemCount: catches.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: HomeDesignLabTokens.space8),
            itemBuilder: (context, index) => _CatchCard(
              key: Key('home-design-lab-catch-card-$index'),
              data: catches[index],
            ),
          ),
        ),
      ],
    );
  }
}

class _CatchData {
  const _CatchData({
    required this.species,
    required this.weight,
    required this.length,
    required this.time,
    required this.privacy,
    required this.icon,
    required this.colors,
  });

  final String species;
  final String weight;
  final String length;
  final String time;
  final String privacy;
  final IconData icon;
  final List<Color> colors;
}

class _CatchCard extends StatelessWidget {
  const _CatchCard({super.key, required this.data});

  final _CatchData data;

  @override
  Widget build(BuildContext context) {
    final copy = _LabCopy.of(context);
    return Semantics(
      label: copy.text(
        ro: '${data.species}, ${data.weight}, ${data.length}, ${data.time}, locație ${data.privacy}. Date demonstrative.',
        en: '${data.species}, ${data.weight}, ${data.length}, ${data.time}, ${data.privacy} location. Demonstration data.',
      ),
      child: Container(
        width: 92,
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.surface,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius16),
          border: Border.all(color: HomeDesignLabTokens.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HomeDesignLabTokens.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: data.colors,
                    ),
                    borderRadius: BorderRadius.circular(
                      HomeDesignLabTokens.radius12,
                    ),
                  ),
                  child: Icon(
                    data.icon,
                    color: HomeDesignLabTokens.primaryText,
                    size: 27,
                  ),
                ),
              ),
              const SizedBox(height: HomeDesignLabTokens.space8),
              Text(
                data.species,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomeDesignLabTokens.primaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: HomeDesignLabTokens.space4),
              Text(
                '${data.weight} • ${data.length}',
                maxLines: 2,
                style: const TextStyle(
                  color: HomeDesignLabTokens.secondaryText,
                  fontSize: 8.5,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: HomeDesignLabTokens.space4),
              Text(
                data.time,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HomeDesignLabTokens.secondaryText,
                  fontSize: 8.5,
                ),
              ),
              const SizedBox(height: HomeDesignLabTokens.space4),
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 10,
                    color: HomeDesignLabTokens.cyanAccent,
                  ),
                  const SizedBox(width: HomeDesignLabTokens.space4),
                  Expanded(
                    child: Text(
                      data.privacy,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomeDesignLabTokens.cyanAccent,
                        fontSize: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({
    super.key,
    required this.semanticLabel,
    required this.child,
    this.padding = HomeDesignLabTokens.space16,
  });

  final String semanticLabel;
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: HomeDesignLabTokens.surface,
          borderRadius: BorderRadius.circular(HomeDesignLabTokens.radius20),
          border: Border.all(color: HomeDesignLabTokens.border),
          boxShadow: const [
            BoxShadow(
              color: HomeDesignLabTokens.shadow,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: HomeDesignLabTokens.cyanAccent, size: 19),
        const SizedBox(width: HomeDesignLabTokens.space8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: HomeDesignLabTokens.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _PremiumIndicator extends StatelessWidget {
  const _PremiumIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HomeDesignLabTokens.space8,
        vertical: HomeDesignLabTokens.space4,
      ),
      decoration: BoxDecoration(
        color: HomeDesignLabTokens.subtleGold,
        borderRadius: BorderRadius.circular(HomeDesignLabTokens.radiusPill),
        border: Border.all(color: HomeDesignLabTokens.premiumGold),
      ),
      child: const Text(
        'PREMIUM',
        style: TextStyle(
          color: HomeDesignLabTokens.premiumGold,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _LocalDataLabel extends StatelessWidget {
  const _LocalDataLabel();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'DEMO LOCAL',
      style: TextStyle(
        color: HomeDesignLabTokens.secondaryText,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: .4,
      ),
    );
  }
}

class _IconText extends StatelessWidget {
  const _IconText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: HomeDesignLabTokens.space4,
        children: [
          Icon(icon, color: HomeDesignLabTokens.secondaryText, size: 13),
          Text(
            label,
            style: const TextStyle(
              color: HomeDesignLabTokens.secondaryText,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: IntrinsicWidth(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: HomeDesignLabTokens.space4,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: HomeDesignLabTokens.cyanAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: HomeDesignLabTokens.cyanAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPreviewPainter extends CustomPainter {
  const _MapPreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = HomeDesignLabTokens.mapBackground;
    canvas.drawRect(Offset.zero & size, background);

    final land = Paint()..color = HomeDesignLabTokens.mapLand;
    final landPath = Path()
      ..moveTo(0, size.height * .18)
      ..quadraticBezierTo(
        size.width * .23,
        size.height * .06,
        size.width * .42,
        size.height * .25,
      )
      ..quadraticBezierTo(
        size.width * .61,
        size.height * .45,
        size.width,
        size.height * .31,
      )
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(landPath, land);

    final water = Paint()
      ..color = HomeDesignLabTokens.mapWater
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(24, size.shortestSide * .11)
      ..strokeCap = StrokeCap.round;
    final riverPath = Path()
      ..moveTo(-20, size.height * .74)
      ..cubicTo(
        size.width * .2,
        size.height * .48,
        size.width * .42,
        size.height * .92,
        size.width * .62,
        size.height * .62,
      )
      ..cubicTo(
        size.width * .76,
        size.height * .42,
        size.width * .87,
        size.height * .55,
        size.width + 20,
        size.height * .38,
      );
    canvas.drawPath(riverPath, water);

    final roads = Paint()
      ..color = HomeDesignLabTokens.mapLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (var index = 1; index < 5; index++) {
      final y = size.height * index / 6;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y + (index.isEven ? 24 : -16)),
        roads,
      );
    }

    final grid = Paint()
      ..color = HomeDesignLabTokens.mapGrid
      ..strokeWidth = 1;
    for (var x = 28.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) => false;
}

class _WaterChartPainter extends CustomPainter {
  const _WaterChartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = HomeDesignLabTokens.mapGrid
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final points = <Offset>[
      Offset(0, size.height * .23),
      Offset(size.width * .15, size.height * .28),
      Offset(size.width * .31, size.height * .35),
      Offset(size.width * .46, size.height * .42),
      Offset(size.width * .61, size.height * .48),
      Offset(size.width * .78, size.height * .59),
      Offset(size.width, size.height * .67),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..color = HomeDesignLabTokens.chartFill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = HomeDesignLabTokens.waterFalling
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WaterChartPainter oldDelegate) => false;
}
