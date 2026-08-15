import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'home_premium_layout.dart';

class HomePremiumHeader extends StatelessWidget {
  const HomePremiumHeader({
    super.key,
    this.notificationCount = 3,
    this.onMenuPressed,
    this.onNotificationPressed,
    this.onLogoLongPress,
    this.subtitle,
    this.subtitleIcon,
    this.subtitleColor,
    this.onSubtitlePressed,
  });

  final int notificationCount;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onNotificationPressed;
  final VoidCallback? onLogoLongPress;
  final String? subtitle;
  final IconData? subtitleIcon;
  final Color? subtitleColor;
  final VoidCallback? onSubtitlePressed;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final effectiveSubtitle = subtitle?.trim();
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );

    return Row(
      children: [
        _HeaderButton(
          icon: Icons.menu_rounded,
          iconSize: 16.4,
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          onTap: onMenuPressed,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            button: onSubtitlePressed != null,
            label: effectiveSubtitle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSubtitlePressed,
              onLongPress: onLogoLongPress,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FluviAiWordmarkAsset(height: 21.5 * layout.titleFontScale),
                  if (effectiveSubtitle != null &&
                      effectiveSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (subtitleIcon != null) ...[
                          Icon(
                            subtitleIcon,
                            size: 10.5 * layout.iconScale,
                            color: subtitleColor ?? const Color(0xFF12D8D6),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            effectiveSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 8.6 * layout.bodyFontScale,
                              height: 1,
                              color: subtitleColor ?? Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _HeaderButton(
              icon: Icons.notifications_none_rounded,
              iconSize: 16,
              tooltip: localizations?.notifications,
              onTap: onNotificationPressed,
            ),
            if (notificationCount > 0)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 12 * layout.iconScale,
                  height: 12 * layout.iconScale,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE53935),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$notificationCount',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 7 * layout.bodyFontScale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FluviAiWordmarkAsset extends StatelessWidget {
  const _FluviAiWordmarkAsset({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FluviAI',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          'assets/branding/fluviai_wordmark.png',
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    this.iconSize,
    this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String? tooltip;
  final double? iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    const buttonSize = 44.0;

    final button = Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: const Color(0xFF08131C).withValues(alpha: .54),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox.square(
            dimension: buttonSize,
            child: Icon(
              icon,
              color: Colors.white,
              size: (iconSize ?? 15) * layout.iconScale,
            ),
          ),
        ),
      ),
    );
    final effectiveTooltip = tooltip;
    return effectiveTooltip == null || effectiveTooltip.isEmpty
        ? button
        : Tooltip(message: effectiveTooltip, child: button);
  }
}
