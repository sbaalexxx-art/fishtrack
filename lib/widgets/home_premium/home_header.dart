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
      height: layout.headerHeight,
      child: Row(
        children: [
          _HeaderButton(icon: Icons.menu_rounded, onTap: onMenuPressed),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onLogoLongPress,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 18 * layout.titleFontScale,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Fluvi',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'AI',
                          style: TextStyle(color: Color(0xFF12D8D6)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Date live • Comunitate • AI',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8 * layout.bodyFontScale,
                      height: 1,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _HeaderButton(
                icon: Icons.notifications_none_rounded,
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

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final layout = HomePremiumLayout.of(context);
    final buttonSize = 30 * layout.iconScale;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Icon(icon, color: Colors.white, size: 17 * layout.iconScale),
        ),
      ),
    );
  }
}
