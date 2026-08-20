import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../services/community_service.dart';
import '../../../services/hydro_dispatch_service.dart';
import '../../../services/location_service.dart';
import '../application/hydro_dispatch_controller.dart';
import 'hydro_dispatch_presentation.dart';

/// Functional bridge between the approved CHE page and the production P3/P4
/// Hydro Dispatch contracts.
///
/// The existing hydropower page remains the visual base. This bridge adds a
/// temporary functional dock so Today/Tomorrow, alerts, field validation,
/// community observations and sanitized AI context are reachable before the
/// dedicated UI polish pass.
///
/// Community evidence is always OBSERVED evidence, never official operator
/// confirmation.
class HydroDispatchRouteBridge extends ConsumerStatefulWidget {
  const HydroDispatchRouteBridge({
    super.key,
    required this.child,
    this.communityService = const CommunityService(),
    this.hydroDispatchService = const HydroDispatchService(),
    this.locationService = const LocationService(),
  });

  final Widget child;
  final CommunityService communityService;
  final HydroDispatchService hydroDispatchService;
  final LocationService locationService;

  @override
  ConsumerState<HydroDispatchRouteBridge> createState() =>
      _HydroDispatchRouteBridgeState();
}

class _HydroDispatchRouteBridgeState
    extends ConsumerState<HydroDispatchRouteBridge> {
  String? _boundPlantId;
  String? _boundPlantName;
  StreamSubscription<CommunityReportEvent>? _reportSubscription;
  final Set<String> _handledReportIds = <String>{};
  bool _handlingReport = false;
  bool _locationMutationRunning = false;

  @override
  void initState() {
    super.initState();
    _reportSubscription = widget.communityService.reportEvents.listen(
      _handleCommunityReportEvent,
    );
  }

  void _bind(SelectedContext? selected) {
    final normalized = selected?.hydropowerPlantId?.trim();
    if (normalized == null || normalized.isEmpty) return;
    _boundPlantName = selected?.locationName ?? selected?.primaryLabel;
    if (normalized == _boundPlantId) return;
    _boundPlantId = normalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _boundPlantId != normalized) return;
      ref.read(hydroDispatchMobileProvider.notifier).refresh(normalized);
    });
  }

  bool get _isRomanian =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';

  Future<void> _handleCommunityReportEvent(CommunityReportEvent event) async {
    final plantId = _boundPlantId;
    if (!mounted ||
        plantId == null ||
        event.type != CommunityReportEventType.created ||
        _handlingReport ||
        _handledReportIds.contains(event.reportId)) {
      return;
    }

    _handledReportIds.add(event.reportId);
    _handlingReport = true;
    try {
      final eventType = await _chooseObservedEvent(
        _boundPlantName ??
            (_isRomanian
                ? 'hidrocentrala selectată'
                : 'selected hydropower plant'),
      );
      if (!mounted || eventType == null) return;

      await widget.hydroDispatchService.submitObservedEvent(
        reportId: event.reportId,
        plantId: plantId,
        eventType: eventType,
        observedAt: DateTime.now(),
        observedAtPrecision: 'reported',
      );

      if (!mounted) return;
      final controller = ref.read(hydroDispatchMobileProvider.notifier);
      final activeValidation = ref.read(
        hydroDispatchMobileProvider.select((state) => state.activeValidation),
      );

      HydroDispatchFieldValidationResult? validationResult;
      if (activeValidation?.plantId == plantId &&
          (eventType == 'turbining_started' ||
              eventType == 'turbining_active')) {
        validationResult = await _finishPositiveValidationIfPossible();
      }

      if (!mounted) return;
      unawaited(controller.refresh(plantId, force: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            validationResult != null
                ? (_isRomanian
                      ? 'Observația OBSERVED a fost legată de Hydro Dispatch și validarea GPS a fost închisă.'
                      : 'The OBSERVED report was linked to Hydro Dispatch and the GPS validation was closed.')
                : (_isRomanian
                      ? 'Observația a fost legată de Hydro Dispatch ca dovadă OBSERVED, nu ca confirmare oficială.'
                      : 'The observation was linked to Hydro Dispatch as OBSERVED evidence, not official confirmation.'),
          ),
        ),
      );
    } on HydroDispatchException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRomanian
                ? 'Raportul a fost publicat, dar observația Hydro nu a putut fi legată: ${error.message}'
                : 'The report was published, but the Hydro observation could not be linked: ${error.message}',
          ),
        ),
      );
    } finally {
      _handlingReport = false;
    }
  }

  Future<HydroDispatchFieldValidationResult?>
  _finishPositiveValidationIfPossible() async {
    if (_locationMutationRunning) return null;
    _locationMutationRunning = true;
    try {
      final position = await widget.locationService.determinePosition();
      if (!mounted) return null;
      return ref
          .read(hydroDispatchMobileProvider.notifier)
          .finishFieldValidation(
            outcome: 'turbining_observed',
            latitude: position.latitude,
            longitude: position.longitude,
          );
    } on Exception {
      return null;
    } finally {
      _locationMutationRunning = false;
    }
  }

  Future<void> _toggleAlert() async {
    final state = ref.read(hydroDispatchMobileProvider);
    final controller = ref.read(hydroDispatchMobileProvider.notifier);
    if (state.isAlertMutationRunning) return;
    if (state.alertEnabled) {
      await controller.disableAlert();
    } else {
      await controller.enableDefaultAlert();
    }
    if (!mounted) return;
    final updated = ref.read(hydroDispatchMobileProvider);
    if (updated.lastError != null) {
      _showError(updated.lastError!);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated.alertEnabled
              ? (_isRomanian
                    ? 'Alerta Hydro Dispatch este activă.'
                    : 'Hydro Dispatch alert is enabled.')
              : (_isRomanian
                    ? 'Alerta Hydro Dispatch este oprită.'
                    : 'Hydro Dispatch alert is disabled.'),
        ),
      ),
    );
  }

  Future<void> _startFieldValidation() async {
    if (_locationMutationRunning) return;
    _locationMutationRunning = true;
    try {
      final position = await widget.locationService.determinePosition();
      if (!mounted) return;
      final result = await ref
          .read(hydroDispatchMobileProvider.notifier)
          .startFieldValidation(
            latitude: position.latitude,
            longitude: position.longitude,
          );
      if (!mounted) return;
      final error = ref.read(hydroDispatchMobileProvider).lastError;
      if (result == null && error != null) {
        _showError(error);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRomanian
                ? 'Validarea de teren a început cu locația GPS reală.'
                : 'Field validation started using the real GPS location.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      _locationMutationRunning = false;
    }
  }

  Future<void> _finishFieldValidation(String outcome) async {
    if (_locationMutationRunning) return;
    _locationMutationRunning = true;
    try {
      final position = await widget.locationService.determinePosition();
      if (!mounted) return;
      final result = await ref
          .read(hydroDispatchMobileProvider.notifier)
          .finishFieldValidation(
            outcome: outcome,
            latitude: position.latitude,
            longitude: position.longitude,
          );
      if (!mounted) return;
      final error = ref.read(hydroDispatchMobileProvider).lastError;
      if (result == null) {
        if (error != null) _showError(error);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.calibrationEligible
                ? (_isRomanian
                      ? 'Validarea a fost închisă și este eligibilă pentru calibrare.'
                      : 'Validation closed and is eligible for calibration.')
                : (_isRomanian
                      ? 'Validarea a fost închisă, dar nu este eligibilă pentru calibrare: ${result.calibrationReason}.'
                      : 'Validation closed but is not calibration-eligible: ${result.calibrationReason}.'),
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      _locationMutationRunning = false;
    }
  }

  void _openObservationReport() {
    AppNavigator.open<void>(context, AppDestination.addReport);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<String?> _chooseObservedEvent(String plantName) {
    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        children: [
          ListTile(
            title: Text(
              _isRomanian
                  ? 'Ai observat o operațiune la $plantName?'
                  : 'Did you observe an operation at $plantName?',
            ),
            subtitle: Text(
              _isRomanian
                  ? 'Opțional. Raportul este deja publicat. Observația comunitară nu este confirmare oficială a operatorului.'
                  : 'Optional. The report is already published. Community observation is not official operator confirmation.',
            ),
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_started',
            icon: Icons.play_circle_outline_rounded,
            label: _isRomanian ? 'Uzinarea a început' : 'Generation started',
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_active',
            icon: Icons.bolt_rounded,
            label: _isRomanian ? 'Uzinare activă acum' : 'Generation active now',
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_stopped',
            icon: Icons.stop_circle_outlined,
            label: _isRomanian ? 'Uzinarea s-a oprit' : 'Generation stopped',
          ),
          _eventTile(
            sheetContext,
            value: 'release_observed',
            icon: Icons.waves_rounded,
            label: _isRomanian ? 'Evacuare observată' : 'Release observed',
          ),
          _eventTile(
            sheetContext,
            value: 'spill_observed',
            icon: Icons.water_rounded,
            label: _isRomanian ? 'Deversare observată' : 'Spill observed',
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(
              _isRomanian ? 'Doar raport general' : 'General report only',
            ),
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    );
  }

  Widget _eventTile(
    BuildContext sheetContext, {
    required String value,
    required IconData icon,
    required String label,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.of(sheetContext).pop(value),
  );

  @override
  void dispose() {
    unawaited(_reportSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedContextProvider);
    _bind(selected);
    final plantId = selected?.hydropowerPlantId?.trim();
    final state = ref.watch(hydroDispatchMobileProvider);

    if (plantId == null || plantId.isEmpty) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        _HydroDispatchFunctionalDock(
          state: state,
          plantName:
              _boundPlantName ?? selected?.locationName ?? 'Hydro Dispatch',
          isRomanian: _isRomanian,
          locationMutationRunning: _locationMutationRunning,
          onRetry: () => ref
              .read(hydroDispatchMobileProvider.notifier)
              .refresh(plantId, force: true),
          onToggleAlert: _toggleAlert,
          onOpenObservationReport: _openObservationReport,
          onStartValidation: _startFieldValidation,
          onFinishNoTurbining: () =>
              _finishFieldValidation('no_turbining_observed'),
          onFinishUnknown: () => _finishFieldValidation('unknown'),
        ),
      ],
    );
  }
}

class _HydroDispatchFunctionalDock extends StatelessWidget {
  const _HydroDispatchFunctionalDock({
    required this.state,
    required this.plantName,
    required this.isRomanian,
    required this.locationMutationRunning,
    required this.onRetry,
    required this.onToggleAlert,
    required this.onOpenObservationReport,
    required this.onStartValidation,
    required this.onFinishNoTurbining,
    required this.onFinishUnknown,
  });

  final HydroDispatchMobileState state;
  final String plantName;
  final bool isRomanian;
  final bool locationMutationRunning;
  final Future<void> Function() onRetry;
  final Future<void> Function() onToggleAlert;
  final VoidCallback onOpenObservationReport;
  final Future<void> Function() onStartValidation;
  final Future<void> Function() onFinishNoTurbining;
  final Future<void> Function() onFinishUnknown;

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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
              children: [
                Expanded(child: _DayCard(data: today)),
                const SizedBox(width: 10),
                Expanded(child: _DayCard(data: tomorrow)),
              ],
            ),
            if (state.lastError != null) ...[
              const SizedBox(height: 10),
              _StatusPanel(
                icon: Icons.sync_problem_rounded,
                title: isRomanian ? 'Conexiune degradată' : 'Degraded connection',
                message: state.lastError!,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: mutationBusy ? null : () => unawaited(onToggleAlert()),
                  icon: Icon(
                    state.alertEnabled
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_none_rounded,
                  ),
                  label: Text(
                    state.alertEnabled
                        ? (isRomanian ? 'Alertă activă' : 'Alert enabled')
                        : (isRomanian ? 'Activează alerta' : 'Enable alert'),
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
            _StatusPanel(
              icon: Icons.auto_awesome_rounded,
              title: isRomanian ? 'Explicație Fluvi' : 'Fluvi explanation',
              message: HydroDispatchPresentation.aiExplanation(
                aiToday,
                isRomanian: isRomanian,
              ),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
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
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (action != null) ...[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      ),
    );
  }
}
