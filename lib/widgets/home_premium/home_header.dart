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
                  _FluviAiWordmark(fontSize: 18 * layout.titleFontScale),
                  const SizedBox(height: 1),
                  Text(
                    Localizations.localeOf(context).languageCode == 'ro'
                        ? 'Pescuit inteligent • Date live • Comunitate'
                        : 'Smart fishing • Live data • Community',
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

class _FluviAiWordmark extends StatelessWidget {
  const _FluviAiWordmark({required this.fontSize});

  static const _silver = Color(0xFFE7EDF3);
  static const _cyan = Color(0xFF12D8D6);

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: fontSize,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
    );
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final text = TextSpan(
      style: style,
      children: const [
        TextSpan(
          text: 'Fluvi',
          style: TextStyle(color: _silver),
        ),
        TextSpan(
          text: 'AI',
          style: TextStyle(color: _cyan),
        ),
      ],
    );
    final textPainter = TextPainter(
      text: text,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();

    return Semantics(
      label: 'FluviAI',
      child: ExcludeSemantics(
        child: CustomPaint(
          size: textPainter.size,
          painter: _FluviAiWordmarkPainter(
            text: text,
            textDirection: textDirection,
            textScaler: textScaler,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}

class _FluviAiWordmarkPainter extends CustomPainter {
  const _FluviAiWordmarkPainter({
    required this.text,
    required this.textDirection,
    required this.textScaler,
    required this.fontSize,
  });

  final TextSpan text;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: text,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final aBoxes = textPainter.getBoxesForSelection(
      const TextSelection(baseOffset: 5, extentOffset: 6),
    );

    canvas.saveLayer(Offset.zero & size, Paint());
    textPainter.paint(canvas, Offset.zero);

    if (aBoxes.isNotEmpty) {
      final aBox = aBoxes.first;
      final crossbarCenter = Offset(
        (aBox.left + aBox.right) / 2,
        aBox.top + ((aBox.bottom - aBox.top) * .58),
      );
      final crossbarHeight = (fontSize * .11).clamp(1.0, 2.4).toDouble();
      final crossbarMask = Rect.fromCenter(
        center: crossbarCenter,
        width: (aBox.right - aBox.left) * .46,
        height: crossbarHeight,
      );

      canvas.drawRect(crossbarMask, Paint()..blendMode = BlendMode.clear);
      canvas.restore();
      canvas.drawCircle(
        crossbarCenter,
        (fontSize * .075).clamp(1.0, 1.8).toDouble(),
        Paint()..color = _FluviAiWordmark._cyan,
      );
      return;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_FluviAiWordmarkPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.fontSize != fontSize;
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
