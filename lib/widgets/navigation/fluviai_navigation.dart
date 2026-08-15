import 'package:flutter/material.dart';

import '../../core/theme/fluviai_commercial_tokens.dart';

enum FluviAIQuickAddSelection { report, catchEntry, savePlace }

class FluviAIBottomNavigationBar extends StatelessWidget {
  const FluviAIBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
  });

  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final colors = FluviAIThemeColors.of(context);

    final navigationShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(
        FluviAICommercialTokens.bottomNavigationRadius,
      ),
      side: BorderSide(color: colors.navigationBorder),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        FluviAICommercialTokens.bottomNavigationHorizontalMargin,
        0,
        FluviAICommercialTokens.bottomNavigationHorizontalMargin,
        6,
      ),
      child: Material(
        key: const ValueKey('bottom-navigation-surface'),
        color: colors.navigationBackground,
        shape: navigationShape,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          key: const ValueKey('main-bottom-navigation'),
          height: FluviAICommercialTokens.bottomNavigationVisualHeight,
          child: Row(
            children: [
              Expanded(
                child: _FluviAINavItem(
                  key: const ValueKey('bottom-nav-home'),
                  icon: Icons.home_outlined,
                  label: isRomanian ? 'Acasă' : 'Home',
                  selected: selectedIndex == 0,
                  onTap: () => onSelect(0),
                ),
              ),
              Expanded(
                child: _FluviAINavItem(
                  key: const ValueKey('bottom-nav-map'),
                  icon: Icons.map_outlined,
                  label: isRomanian ? 'Hartă' : 'Map',
                  selected: selectedIndex == 1,
                  onTap: () => onSelect(1),
                ),
              ),
              Semantics(
                key: const ValueKey('bottom-nav-quick-add'),
                button: true,
                label: isRomanian ? 'Adaugă' : 'Add',
                child: SizedBox(
                  width: FluviAICommercialTokens.bottomNavigationQuickAddWidth,
                  height: FluviAICommercialTokens.bottomNavigationVisualHeight,
                  child: Align(
                    alignment: Alignment.center,
                    child: Material(
                      key: const ValueKey('bottom-nav-quick-add-visual'),
                      color: FluviAICommercialTokens.brandFocus,
                      borderRadius: BorderRadius.circular(
                        FluviAICommercialTokens.bottomNavigationQuickAddRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: onAdd,
                        child: SizedBox(
                          width: FluviAICommercialTokens
                              .bottomNavigationQuickAddVisualHeight,
                          height: FluviAICommercialTokens
                              .bottomNavigationQuickAddVisualHeight,
                          child: Icon(
                            Icons.add_rounded,
                            size: 22,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _FluviAINavItem(
                  key: const ValueKey('bottom-nav-activity'),
                  icon: Icons.ssid_chart_rounded,
                  label: isRomanian ? 'Activitate' : 'Activity',
                  selected: selectedIndex == 2,
                  onTap: () => onSelect(2),
                ),
              ),
              Expanded(
                child: _FluviAINavItem(
                  key: const ValueKey('bottom-nav-utilities'),
                  icon: Icons.grid_view_rounded,
                  label: isRomanian ? 'Utilități' : 'Utilities',
                  selected: selectedIndex == 3,
                  onTap: () => onSelect(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluviAINavItem extends StatelessWidget {
  const _FluviAINavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    final foreground = selected
        ? (Theme.of(context).brightness == Brightness.dark
              ? FluviAICommercialTokens.brandFocus
              : FluviAICommercialTokens.accentDeep)
        : colors.navigationInactive;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: SizedBox(
        height: FluviAICommercialTokens.bottomNavigationVisualHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: FluviAICommercialTokens.bottomNavigationIconSize,
                    color: foreground,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: FluviAICommercialTokens.primaryFontFamily,
                      color: foreground,
                      fontSize:
                          FluviAICommercialTokens.bottomNavigationLabelSize,
                      height: 14 / 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FluviAIQuickAddSheet extends StatelessWidget {
  const FluviAIQuickAddSheet({
    super.key,
    required this.onAddReport,
    required this.onAddCatch,
    required this.onSavePlace,
  });

  final VoidCallback onAddReport;
  final VoidCallback onAddCatch;
  final VoidCallback onSavePlace;

  @override
  Widget build(BuildContext context) {
    final isRomanian =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final colors = FluviAIThemeColors.of(context);

    return Semantics(
      container: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          12 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textMuted,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isRomanian ? 'Adaugă' : 'Add',
                    style: TextStyle(
                      fontFamily: FluviAICommercialTokens.fontFamily,
                      color: colors.textPrimary,
                      fontSize: 20,
                      height: 24 / 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: FluviAICommercialTokens.minimumTouchTarget,
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.cancel_outlined, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: largeText ? 1.0 : 1.24,
              children: [
                _AddDestinationTile(
                  key: const ValueKey('quick-add-report'),
                  icon: Icons.outlined_flag_rounded,
                  title: isRomanian ? 'Raport' : 'Report',
                  subtitle: isRomanian
                      ? 'Raportează o situație'
                      : 'Report a situation',
                  accent: FluviAICommercialTokens.warning,
                  onTap: onAddReport,
                ),
                _AddDestinationTile(
                  key: const ValueKey('quick-add-catch'),
                  icon: Icons.photo_camera_outlined,
                  title: isRomanian ? 'Captură' : 'Catch',
                  subtitle: isRomanian ? 'Adaugă o captură' : 'Add a catch',
                  accent: FluviAICommercialTokens.brandFocus,
                  onTap: onAddCatch,
                ),
                _AddDestinationTile(
                  key: const ValueKey('quick-add-save-place'),
                  icon: Icons.location_on_outlined,
                  title: isRomanian ? 'Loc salvat' : 'Saved place',
                  subtitle: isRomanian ? 'Salvează un loc' : 'Save a place',
                  accent: const Color(0xFF29B6F6),
                  onTap: onSavePlace,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(isRomanian ? 'Anulează' : 'Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddDestinationTile extends StatelessWidget {
  const _AddDestinationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Tooltip(
      message: title,
      child: Semantics(
        button: true,
        label: title,
        value: subtitle,
        excludeSemantics: true,
        child: Material(
          color: colors.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent.withValues(alpha: .24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FluviAICommercialTokens.fontFamily,
                      color: colors.textPrimary,
                      fontSize: 15,
                      height: 18 / 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FluviAICommercialTokens.fontFamily,
                      color: colors.textSecondary,
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
