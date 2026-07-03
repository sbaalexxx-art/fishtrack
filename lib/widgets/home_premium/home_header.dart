import 'package:flutter/material.dart';

class HomePremiumHeader extends StatelessWidget {
  const HomePremiumHeader({
    super.key,
    this.notificationCount = 3,
    this.onMenuPressed,
    this.onNotificationPressed,
  });

  final int notificationCount;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onNotificationPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          _HeaderButton(icon: Icons.menu_rounded, onTap: onMenuPressed),

          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text.rich(
                    const TextSpan(
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.4,
                      ),
                      children: [
                        TextSpan(
                          text: 'AI',
                          style: TextStyle(color: Color(0xFF2B7FFF)),
                        ),
                        TextSpan(
                          text: 'Fish',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Map',
                          style: TextStyle(color: Color(0xFF67D04B)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Designed by anglers',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Stack(
            clipBehavior: Clip.none,
            children: [
              _HeaderButton(
                icon: Icons.notifications_none_rounded,
                onTap: onNotificationPressed,
              ),
              if (notificationCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 16,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFF67D04B),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$notificationCount',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 8,
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
    return Material(
      color: const Color(0xFF1A1F27),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
