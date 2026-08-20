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

  @override
  Widget build(BuildContext context) {
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
    final colors = Theme.of(context).colorScheme;
    final mutationBusy =
        state.isLoading ||
        state.isAlertMutationRunning ||
        state.isValidationMutationRunning ||
        locationMutationRunning;

    return DraggableScrollableSheet(
      initialChildSize: .16,
      minChildSize: .105,
      maxChildSize: .74,
      snap: true,
      snapSizes: const [.16, .42, .74],
      builder: (context, scrollController) => Material(
        elevation: 18,
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hydro Dispatch · $plantName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        observed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (state.isLoading)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: isRomanian ? 'Actualizează' : 'Refresh',
                    onPressed: () => unawaited(onRetry()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _DayCard(data: today)),
                const SizedBox(width: 10),
                Expanded(
                  child: isPremium
                      ? _DayCard(data: tomorrow)
                      : _PremiumLockCard(
                          isRomanian: isRomanian,
                          title: isRomanian ? 'Mâine' : 'Tomorrow',
                          onOpenPremium: onOpenPremium,
                        ),
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
                      : isPremium
                      ? () => unawaited(onToggleAlert())
                      : onOpenPremium,
                  icon: Icon(
                    isPremium && state.alertEnabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                  ),
                  label: Text(
                    isPremium
                        ? state.alertEnabled
                              ? (isRomanian ? 'Alertă activă' : 'Alert enabled')
                              : (isRomanian
                                    ? 'Activează alerta'
                                    : 'Enable alert')
                        : (isRomanian
                              ? 'Alerte · Premium'
                              : 'Alerts · Premium'),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: mutationBusy ? null : onOpenObservationReport,
                  icon: const Icon(Icons.add_location_alt_rounded),
                  label: Text(isRomanian ? 'Raport din teren' : 'Field report'),
                ),
              ],
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
            const SizedBox(height: 14),
            if (isPremium)
              _StatusPanel(
                icon: Icons.auto_awesome_rounded,
                title: isRomanian ? 'Explicație Fluvi' : 'Fluvi explanation',
                message: HydroDispatchPresentation.aiExplanation(
                  aiToday,
                  isRomanian: isRomanian,
                ),
              )
            else
              _PremiumLockCard(
                isRomanian: isRomanian,
                title: isRomanian
                    ? 'Explicație Hydro avansată'
                    : 'Advanced Hydro explanation',
                onOpenPremium: onOpenPremium,
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
            const SizedBox(height: 10),
            Text(
              isRomanian
                  ? 'Probabilitățile sunt estimări. OBSERVED înseamnă observație comunitară în teren, nu confirmare oficială Hidroelectrica/operator.'
                  : 'Probabilities are estimates. OBSERVED means community field evidence, not official Hidroelectrica/operator confirmation.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.data});

  final HydroDispatchDayPresentation data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.dayLabel.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Text(
            data.probabilityLabel,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            data.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 5),
          Text(
            data.available ? data.windowLabel : data.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            '${data.evidenceLabel} · ${data.confidenceLabel}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _PremiumLockCard extends StatelessWidget {
  const _PremiumLockCard({
    required this.isRomanian,
    required this.title,
    required this.onOpenPremium,
  });

  final bool isRomanian;
  final String title;
  final VoidCallback onOpenPremium;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpenPremium,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .36),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.workspace_premium_rounded, size: 20),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              isRomanian ? 'Disponibil în Premium' : 'Available in Premium',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
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
            ? 'Pornește doar când ești fizic lângă CHE. Backendul verifică distanța și păstrează snapshotul predicției înainte de observație.'
            : 'Start only when physically near the plant. The backend verifies distance and freezes the prediction snapshot before observation.',
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
          ? 'Pentru rezultat pozitiv publică un raport „uzinare începută/activă”. Pentru rezultat negativ, rămâi în teren suficient timp și închide sesiunea mai jos.'
          : 'For a positive result publish a “generation started/active” field report. For a negative result remain on site long enough and close the session below.',
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}
