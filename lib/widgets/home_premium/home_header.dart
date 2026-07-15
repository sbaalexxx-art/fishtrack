import 'package:flutter/material.dart';

import 'home_premium_layout.dart';

class HomePremiumHeader extends StatelessWidget {
  const HomePremiumHeader({
    super.key,
    this.notificationCount = 3,
    this.onMenuPressed,
    this.onNotificationPressed,
    this.onLogoLongPress,
  });

  final int notificationCount;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onNotificationPressed;
  final VoidCallback? onLogoLongPress;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);

    return SizedBox(
      height: layout.headerHeight * .70,
      child: Row(
        children: [
          _HeaderButton(
            icon: Icons.menu_rounded,
            iconSize: 16.4,
            onTap: onMenuPressed,
          ),
          const SizedBox(width: 4),
          _FluviAiLogo(height: 31 * layout.iconScale),
          const SizedBox(width: 7),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onLogoLongPress,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FluviAiWordmarkAsset(height: 21.5 * layout.titleFontScale),
                  const SizedBox(height: 1),
                  Text(
                    'Acolo unde pasiunea întâlnește firul apei.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.8 * layout.bodyFontScale,
                      height: 1,
                      color: Colors.white.withValues(alpha: .92),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
      ),
    );
  }
}

class _FluviAiLogo extends StatelessWidget {
  const _FluviAiLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FluviAI',
      image: true,
      child: ExcludeSemantics(
        child: Image.asset(
          'assets/branding/fluviai_logo.png',
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
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
  const _HeaderButton({required this.icon, this.iconSize, this.onTap});

  final IconData icon;
  final double? iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final buttonSize = 26 * layout.iconScale;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Icon(
            icon,
            color: Colors.white,
            size: (iconSize ?? 15) * layout.iconScale,
          ),
        ),
      ),
    );
  }
}
