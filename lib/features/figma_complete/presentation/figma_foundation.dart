import 'package:flutter/material.dart';

import '../../../core/theme/fluviai_commercial_tokens.dart';

abstract final class FigmaFluviTokens {
  static const background = FluviAICommercialTokens.background;
  static const backgroundAlt = FluviAICommercialTokens.backgroundRaised;
  static const surface = FluviAICommercialTokens.surface;
  static const surfaceRaised = FluviAICommercialTokens.surfaceRaised;
  static const surfaceSoft = FluviAICommercialTokens.surfaceStrong;
  static const cyan = FluviAICommercialTokens.brandFocus;
  static const cyanSoft = Color(0xFF60F0C2);
  static const white = FluviAICommercialTokens.textPrimary;
  static const textSecondary = FluviAICommercialTokens.textSecondary;
  static const textMuted = FluviAICommercialTokens.textMuted;
  static const border = FluviAICommercialTokens.borderSoft;
  static const green = FluviAICommercialTokens.waterStable;
  static const amber = FluviAICommercialTokens.warning;
  static const red = FluviAICommercialTokens.waterFalling;
  static const warning = FluviAICommercialTokens.warning;
  static const violet = Color(0xFFB3A7FF);

  static const pageGradient = FluviAICommercialTokens.pageGradient;

  static const mapGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A2537), Color(0xFF071625), Color(0xFF030B14)],
  );
}

class FigmaCanonicalScaffold extends StatelessWidget {
  const FigmaCanonicalScaffold({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.subtitle,
    this.subtitleColor,
    this.action,
    this.showBack = true,
    this.background,
    this.scaffoldColor,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 28),
    this.extendBodyBehindAppBar = false,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget child;
  final Widget? action;
  final bool showBack;
  final Decoration? background;
  final Color? scaffoldColor;
  final EdgeInsetsGeometry padding;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = FluviAIThemeColors.of(context);
    final pageColor = scaffoldColor ?? theme.scaffoldBackgroundColor;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Scaffold(
      backgroundColor: pageColor,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: extendBodyBehindAppBar
            ? Colors.transparent
            : pageColor.withValues(alpha: .96),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: largeText ? 76 : 56,
        leadingWidth: showBack ? 56 : 20,
        leading: showBack
            ? SizedBox(
                key: const ValueKey('figma-back-button-target'),
                width: 48,
                height: 48,
                child: Center(
                  child: Material(
                    key: const ValueKey('figma-back-button'),
                    color: theme.colorScheme.surfaceContainerHigh.withValues(
                      alpha: .72,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.maybePop(context),
                      child: SizedBox.square(
                        dimension: 36,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        titleSpacing: showBack ? 0 : 20,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null)
              Text(
                eyebrow!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FigmaFluviTokens.cyan,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.15,
                ),
              ),
            Text(
              title,
              maxLines: largeText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -.25,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: subtitleColor ?? colors.textSecondary,
                  fontFamily: subtitleColor == null
                      ? FluviAICommercialTokens.primaryFontFamily
                      : FluviAICommercialTokens.monoFontFamily,
                  fontSize: subtitleColor == null ? 10 : 8.5,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: subtitleColor == null ? 0 : .25,
                ),
              ),
            ],
          ],
        ),
        actions: action == null
            ? const []
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: action,
                ),
              ],
      ),
      body: DecoratedBox(
        decoration: background ?? BoxDecoration(gradient: colors.pageGradient),
        child: SafeArea(
          top: extendBodyBehindAppBar,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class FigmaRoundButton extends StatelessWidget {
  const FigmaRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.foreground,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: SizedBox.square(
        dimension: 44,
        child: Material(
          color: active
              ? FigmaFluviTokens.cyan.withValues(alpha: .16)
              : colors.surfaceRaised.withValues(alpha: .90),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: active
                  ? FigmaFluviTokens.cyan.withValues(alpha: .55)
                  : FigmaFluviTokens.cyan.withValues(alpha: .12),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: 21,
              color:
                  foreground ??
                  (active ? FigmaFluviTokens.cyan : colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class FigmaSurface extends StatelessWidget {
  const FigmaSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.accent,
    this.onTap,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final color = accent ?? FigmaFluviTokens.cyan;
    final colors = FluviAIThemeColors.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: .94),
          borderRadius: borderRadius,
          border: Border.all(color: color.withValues(alpha: .14)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2A000000),
              blurRadius: 18,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class FigmaSectionLabel extends StatelessWidget {
  const FigmaSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: FigmaFluviTokens.cyan,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class FigmaPill extends StatelessWidget {
  const FigmaPill({
    super.key,
    required this.label,
    this.icon,
    this.color = FigmaFluviTokens.cyan,
    this.active = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final colors = FluviAIThemeColors.of(context);
    final child = Container(
      constraints: BoxConstraints(minHeight: largeText ? 48 : 36),
      padding: EdgeInsets.symmetric(
        horizontal: 13,
        vertical: largeText ? 10 : 8,
      ),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: .16) : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? color.withValues(alpha: .72)
              : color.withValues(alpha: .12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: active ? color : colors.textSecondary, size: 15),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: largeText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              softWrap: largeText,
              style: TextStyle(
                color: active ? color : colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

class FigmaMetric extends StatelessWidget {
  const FigmaMetric({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.alignment = CrossAxisAlignment.start,
    this.valueColor,
  });

  final String value;
  final String label;
  final IconData? icon;
  final CrossAxisAlignment alignment;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final colors = FluviAIThemeColors.of(context);
    return Column(
      crossAxisAlignment: largeText ? CrossAxisAlignment.start : alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: largeText ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: FigmaFluviTokens.cyan),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                value,
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                softWrap: largeText,
                style: TextStyle(
                  color: valueColor ?? colors.textPrimary,
                  fontSize: 17,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label.toUpperCase(),
          maxLines: largeText ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          softWrap: largeText,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 9,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: .55,
          ),
        ),
      ],
    );
  }
}

class FigmaTruthfulEmpty extends StatelessWidget {
  const FigmaTruthfulEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionKey,
    this.onAction,
    this.minHeight = 0,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: FigmaSurface(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: FigmaFluviTokens.cyan.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: FigmaFluviTokens.cyan, size: 28),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    key: actionKey,
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FigmaStatusDot extends StatelessWidget {
  const FigmaStatusDot({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: largeText ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 9,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
        ),
      ],
    );
  }
}

class FigmaPrimaryButton extends StatelessWidget {
  const FigmaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? FigmaFluviTokens.red : FigmaFluviTokens.cyan;
    final colors = FluviAIThemeColors.of(context);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      backgroundColor: WidgetStatePropertyAll(
        secondary ? colors.surfaceRaised : color,
      ),
      foregroundColor: WidgetStatePropertyAll(
        secondary ? color : colors.background,
      ),
      side: secondary
          ? WidgetStatePropertyAll(
              BorderSide(color: color.withValues(alpha: .35)),
            )
          : null,
    );
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final labelWidget = Text(
      label,
      maxLines: largeText ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    return icon == null
        ? FilledButton(style: style, onPressed: onPressed, child: labelWidget)
        : FilledButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: labelWidget,
          );
  }
}

class FigmaDivider extends StatelessWidget {
  const FigmaDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: FluviAIThemeColors.of(context).borderSoft,
  );
}

class FigmaMiniChart extends StatelessWidget {
  const FigmaMiniChart({
    super.key,
    required this.values,
    this.color = FigmaFluviTokens.cyan,
  });

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = FluviAIThemeColors.of(context);
    return CustomPaint(
      painter: _FigmaMiniChartPainter(
        values: values,
        color: color,
        pointColor: colors.textPrimary,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _FigmaMiniChartPainter extends CustomPainter {
  const _FigmaMiniChartPainter({
    required this.values,
    required this.color,
    required this.pointColor,
  });

  final List<double> values;
  final Color color;
  final Color pointColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = (maxValue - minValue).abs() < .0001
        ? 1.0
        : maxValue - minValue;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final normalized = (values[i] - minValue) / range;
      final y = size.height - (normalized * (size.height - 14)) - 7;
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final controlX = (previous.dx + current.dx) / 2;
      path.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 4.5, Paint()..color = color);
    canvas.drawCircle(points.last, 2, Paint()..color = pointColor);
  }

  @override
  bool shouldRepaint(covariant _FigmaMiniChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.pointColor != pointColor;
}

TextStyle figmaTitle({
  Color color = FigmaFluviTokens.white,
  double size = 20,
  FontWeight weight = FontWeight.w800,
  double height = 1.15,
}) => TextStyle(
  fontFamily: FluviAICommercialTokens.fontFamily,
  color: color,
  fontSize: size,
  height: height,
  fontWeight: weight,
  letterSpacing: -.2,
);

TextStyle figmaBody({
  Color color = FigmaFluviTokens.textSecondary,
  double size = 12,
  FontWeight weight = FontWeight.w500,
  double height = 1.4,
}) => TextStyle(
  fontFamily: FluviAICommercialTokens.fontFamily,
  color: color,
  fontSize: size,
  height: height,
  fontWeight: weight,
);
