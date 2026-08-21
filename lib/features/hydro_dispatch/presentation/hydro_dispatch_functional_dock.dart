import 'dart:async';

import 'package:flutter/material.dart';

import '../application/hydro_dispatch_controller.dart';
import 'hydro_dispatch_presentation.dart';

class HydroDispatchFunctionalDock extends StatelessWidget {
  const HydroDispatchFunctionalDock({
    super.key,
    required this.state,
    required this.plantName,
    required this.isRomanian,
    required this.isPremium,
    required this.locationMutationRunning,
    required this.onRetry,
    required this.onToggleAlert,
    required this.onOpenObservationReport,
    required this.onStartValidation,
    required this.onFinishNoTurbining,
    required this.onFinishUnknown,
    required this.onOpenPremium,
  });

  static const _surface = Color(0xFF081218);
  static const _card = Color(0xFF102029);
  static const _cardStrong = Color(0xFF132831);
  static const _border = Color(0xFF28434D);
  static const _cyan = Color(0xFFE8C878);
  static const _white = Color(0xFFF6F9FB);
  static const _secondary = Color(0xFFA7BBC5);
  static const _muted = Color(0xFF78909C);
  static const _amber = Color(0xFFF0B94B);

  final HydroDispatchMobileState state;
  final String plantName;
  final bool isRomanian;
  final bool isPremium;
  final bool locationMutationRunning;
  final Future<void> Function() onRetry;
  final Future<void> Function() onToggleAlert;
  final VoidCallback onOpenObservationReport;
  final Future<void> Function() onStartValidation;
  final Future<void> Function() onFinishNoTurbining;
  final Future<void> Function() onFinishUnknown;
  final VoidCallback onOpenPremium;

  ThemeData _dockTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        surface: _surface,
        surfaceContainerHighest: _card,
        onSurface: _white,
        onSurfaceVariant: _secondary,
        outlineVariant: _border,
        primary: _cyan,
        onPrimary: const Color(0xFF021513),
      ),
      textTheme: base.textTheme.apply(bodyColor: _white, displayColor: _white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themed = _dockTheme(context);
    if (!isPremium) {
      return Theme(
        data: themed,
        child: DraggableScrollableSheet(
          key: const ValueKey('hydro-dispatch-functional-dock-locked'),
          initialChildSize: .30,
          minChildSize: .24,
          maxChildSize: .45,
          snap: true,
          snapSizes: const [.30, .45],
          builder: (context, scrollController) => Material(
            elevation: 22,
            color: _surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 28),
              children: [
                const _DockHandle(),
                const SizedBox(height: 14),
                Text(
                  'Hydro PRO · $plantName',
                  style: const TextStyle(
                    color: _white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isRomanian
                      ? 'Harta Hydro, probabilitatea de uzinare, intervalele estimate, AI/ML și notificările Hydro sunt funcții Pro.'
                      : 'Hydro Map, generation probability, estimated windows, Hydro AI/ML and notifications are Pro features.',
                  style: const TextStyle(color: _secondary, height: 1.35),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onOpenPremium,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: Text(isRomanian ? 'Vezi Hydro Pro' : 'View Hydro Pro'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final today = HydroDispatchPresentation.day(
      state.today,
      isRomanian: isRomanian,
    );
    final tomorrow = HydroDispatchPresentation.day(
      state.tomorrow,
      isRomanian: isRomanian,
    );
    final aiToday = state.aiContext
        .where((item) => item.dayOffset == 0)
        .firstOrNull;
    final observed = HydroDispatchPresentation.observedLabel(
      aiToday,
      isRomanian: isRomanian,
    );
    final mutationBusy =
        state.isLoading ||
        state.isAlertMutationRunning ||
        state.isValidationMutationRunning ||
        locationMutationRunning;

    return Theme(
      data: themed,
      child: DraggableScrollableSheet(
        key: const ValueKey('hydro-dispatch-functional-dock'),
        // Product QA must see the actual forecast immediately. The previous
        // 16% initial size could visually disappear into the legacy CHE page.
        initialChildSize: .44,
        minChildSize: .30,
        maxChildSize: .82,
        snap: true,
        snapSizes: const [.44, .82],
        builder: (context, scrollController) => Material(
          elevation: 24,
          color: _surface,
          shadowColor: Colors.black.withValues(alpha: .75),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _cyan, width: 1.1)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 9, 18, 30),
              children: [
                const _DockHandle(),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _cyan.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cyan.withValues(alpha: .45)),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: _cyan),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hydro Dispatch · $plantName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _white,
                              fontSize: 18,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            observed,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _cyan,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: isRomanian ? 'Actualizează' : 'Refresh',
                        onPressed: () => unawaited(onRetry()),
                        color: _cyan,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.usingPersistedCache)
                  _TruthStrip(
                    icon: Icons.offline_bolt_rounded,
                    text: isRomanian
                        ? 'CACHE · ultima predicție validă salvată'
                        : 'CACHE · last valid saved prediction',
                    color: _amber,
                  ),
                if (state.usingPersistedCache) const SizedBox(height: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DayCard(
                      data: today,
                      primary: true,
                      isRomanian: isRomanian,
                    ),
                    const SizedBox(height: 10),
                    _DayCard(
                      data: tomorrow,
                      primary: false,
                      isRomanian: isRomanian,
                    ),
                  ],
                ),
                if (state.lastError != null) ...[
                  const SizedBox(height: 10),
                  _StatusPanel(
                    icon: Icons.sync_problem_rounded,
                    title: isRomanian
                        ? 'Conexiune degradată'
                        : 'Degraded connection',
                    message: state.lastError!,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: mutationBusy
                          ? null
                          : () => unawaited(onToggleAlert()),
                      icon: Icon(
                        state.alertEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                      ),
                      label: Text(
                        state.alertEnabled
                            ? (isRomanian ? 'Alertă activă' : 'Alert enabled')
                            : (isRomanian
                                  ? 'Activează alerta'
                                  : 'Enable alert'),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: mutationBusy ? null : onOpenObservationReport,
                      icon: const Icon(Icons.add_location_alt_rounded),
                      label: Text(
                        isRomanian ? 'Raport din teren' : 'Field report',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _StatusPanel(
                  icon: Icons.auto_awesome_rounded,
                  title: isRomanian
                      ? 'Explicație Fluvi AI'
                      : 'Fluvi AI explanation',
                  message: HydroDispatchPresentation.aiExplanation(
                    aiToday,
                    isRomanian: isRomanian,
                  ),
                ),
                const SizedBox(height: 14),
                _FieldValidationPanel(
                  state: state,
                  isRomanian: isRomanian,
                  busy: mutationBusy,
                  onStart: onStartValidation,
                  onNoTurbining: onFinishNoTurbining,
                  onUnknown: onFinishUnknown,
                  onPositiveReport: onOpenObservationReport,
                ),
                if (state.lastCompletedValidation case final result?) ...[
                  const SizedBox(height: 12),
                  _StatusPanel(
                    icon: result.calibrationEligible
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    title: isRomanian
                        ? 'Ultima validare de teren'
                        : 'Last field validation',
                    message: result.calibrationEligible
                        ? (isRomanian
                              ? 'Eligibilă pentru calibrare · ${result.durationMinutes.toStringAsFixed(0)} min.'
                              : 'Calibration eligible · ${result.durationMinutes.toStringAsFixed(0)} min.')
                        : (isRomanian
                              ? 'Neeligibilă pentru calibrare · ${result.calibrationReason}.'
                              : 'Not calibration eligible · ${result.calibrationReason}.'),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  isRomanian
                      ? 'Probabilitățile sunt estimări, nu confirmări oficiale. OBSERVED înseamnă observație comunitară în teren.'
                      : 'Probabilities are estimates, not official confirmations. OBSERVED means community field evidence.',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockHandle extends StatelessWidget {
  const _DockHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 46,
      height: 4,
      decoration: BoxDecoration(
        color: HydroDispatchFunctionalDock._secondary,
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

class _TruthStrip extends StatelessWidget {
  const _TruthStrip({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: .42)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.data,
    required this.primary,
    required this.isRomanian,
  });

  final HydroDispatchDayPresentation data;
  final bool primary;
  final bool isRomanian;

  @override
  Widget build(BuildContext context) {
    final accent = primary
        ? HydroDispatchFunctionalDock._cyan
        : HydroDispatchFunctionalDock._secondary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primary
            ? HydroDispatchFunctionalDock._cardStrong
            : HydroDispatchFunctionalDock._card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.dayLabel.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: 10,
              letterSpacing: .7,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            data.probabilityLabel,
            style: const TextStyle(
              color: HydroDispatchFunctionalDock._white,
              fontSize: 26,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            data.available
                ? data.windowLabel
                : (isRomanian
                      ? 'Predicție indisponibilă'
                      : 'Forecast unavailable'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HydroDispatchFunctionalDock._white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HydroDispatchFunctionalDock._secondary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${data.evidenceLabel} · ${data.confidenceLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HydroDispatchFunctionalDock._muted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldValidationPanel extends StatelessWidget {
  const _FieldValidationPanel({
    required this.state,
    required this.isRomanian,
    required this.busy,
    required this.onStart,
    required this.onNoTurbining,
    required this.onUnknown,
    required this.onPositiveReport,
  });

  final HydroDispatchMobileState state;
  final bool isRomanian;
  final bool busy;
  final Future<void> Function() onStart;
  final Future<void> Function() onNoTurbining;
  final Future<void> Function() onUnknown;
  final VoidCallback onPositiveReport;

  @override
  Widget build(BuildContext context) {
    final active = state.activeValidation;
    if (active == null) {
      return _StatusPanel(
        icon: Icons.gps_fixed_rounded,
        title: isRomanian ? 'Validare GPS în teren' : 'GPS field validation',
        message: isRomanian
            ? 'Pornește numai când ești fizic lângă CHE. Backendul verifică distanța și îngheață predicția înainte de observație.'
            : 'Start only when physically near the plant. The backend verifies distance and freezes the prediction before observation.',
        action: FilledButton.icon(
          onPressed: busy ? null : () => unawaited(onStart()),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(isRomanian ? 'Pornește validarea' : 'Start validation'),
        ),
      );
    }

    return _StatusPanel(
      icon: Icons.gps_fixed_rounded,
      title: isRomanian ? 'Validare GPS activă' : 'GPS validation active',
      message: isRomanian
          ? 'Pentru rezultat pozitiv publică observația de uzinare. Pentru rezultat negativ rămâi în teren suficient timp și închide sesiunea.'
          : 'For a positive result publish the generation observation. For a negative result remain on site long enough and close the session.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : onPositiveReport,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(
              isRomanian ? 'Am observat uzinare' : 'Generation observed',
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => unawaited(onNoTurbining()),
            icon: const Icon(Icons.visibility_off_outlined),
            label: Text(
              isRomanian ? 'Nu s-a uzinat' : 'No generation observed',
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => unawaited(onUnknown()),
            child: Text(isRomanian ? 'Încheie necunoscut' : 'Finish unknown'),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: HydroDispatchFunctionalDock._card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: HydroDispatchFunctionalDock._border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: HydroDispatchFunctionalDock._cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: HydroDispatchFunctionalDock._white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          message,
          style: const TextStyle(
            color: HydroDispatchFunctionalDock._secondary,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 10), action!],
      ],
    ),
  );
}
