import 'package:flutter/material.dart';

import '../../core/theme/app_dimensions.dart';
import '../../core/theme/fluviai_commercial_tokens.dart';

enum FluviDataStatus { live, cache, offline, error, loading, empty }

enum FluviResponsiveClass { compact, phone, wide, tablet, landscape }

FluviResponsiveClass fluviResponsiveClass(BuildContext context) {
  if (AppDimensions.isCompactLandscape(context)) {
    return FluviResponsiveClass.landscape;
  }
  if (AppDimensions.isCompact(context)) return FluviResponsiveClass.compact;
  if (AppDimensions.isPhone(context)) return FluviResponsiveClass.phone;
  if (AppDimensions.isTablet(context)) return FluviResponsiveClass.tablet;
  return FluviResponsiveClass.wide;
}

class FluviScreen extends StatelessWidget {
  const FluviScreen({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.actions = const [],
    this.bottom,
    this.showBack = true,
    this.floatingActionButton,
  });

  final String title;
  final String? eyebrow;
  final Widget child;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool showBack;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: FluviAICommercialTokens.background,
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: showBack ? 0 : 18,
        backgroundColor: FluviAICommercialTokens.backgroundRaised,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: FluviAICommercialTokens.textPrimary,
          size: 22,
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: Divider(
            height: 1,
            thickness: 1,
            color: FluviAICommercialTokens.borderSoft,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (eyebrow != null)
              Text(
                eyebrow!.toUpperCase(),
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                height: 22 / 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -.1,
              ),
            ),
          ],
        ),
        actions: actions,
        bottom: bottom,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: FluviAICommercialTokens.pageGradient,
        ),
        child: SafeArea(top: false, child: child),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class FluviSurfaceCard extends StatelessWidget {
  const FluviSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(FluviAICommercialTokens.radiusLarge);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: FluviAICommercialTokens.surfaceGradient(accent: accent),
          borderRadius: radius,
          border: Border.all(color: FluviAICommercialTokens.borderSoft),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 14,
              offset: Offset(0, 8),
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

class FluviStatusBadge extends StatelessWidget {
  const FluviStatusBadge({super.key, required this.status, this.label});

  final FluviDataStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (color, fallback) = switch (status) {
      FluviDataStatus.live => (FluviAICommercialTokens.waterStable, 'LIVE'),
      FluviDataStatus.cache => (FluviAICommercialTokens.warning, 'CACHE'),
      FluviDataStatus.offline => (FluviAICommercialTokens.textMuted, 'OFFLINE'),
      FluviDataStatus.error => (FluviAICommercialTokens.waterFalling, 'ERROR'),
      FluviDataStatus.loading => (
        FluviAICommercialTokens.brandFocus,
        'LOADING',
      ),
      FluviDataStatus.empty => (FluviAICommercialTokens.textMuted, 'NO DATA'),
    };
    return Semantics(
      label: label ?? fallback,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .42)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label ?? fallback,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FluviStatePanel extends StatelessWidget {
  const FluviStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FluviSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: FluviAICommercialTokens.brandFocus, size: 42),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: FluviAICommercialTokens.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FluviMapControl extends StatelessWidget {
  const FluviMapControl({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? FluviAICommercialTokens.brandFocus
        : FluviAICommercialTokens.textPrimary;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: active,
      label: label,
      child: SizedBox.square(
        dimension: AppDimensions.minimumTouchTarget,
        child: Center(
          child: Material(
            color: active
                ? FluviAICommercialTokens.accentDeep
                : FluviAICommercialTokens.surfaceStrong,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox.square(
                dimension: AppDimensions.mapControlVisualSize,
                child: Icon(
                  icon,
                  color: onPressed == null
                      ? FluviAICommercialTokens.textMuted
                      : color,
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
