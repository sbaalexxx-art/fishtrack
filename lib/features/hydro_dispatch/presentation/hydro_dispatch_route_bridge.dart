import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../core/map/pending_map_camera.dart';
import '../../../core/navigation/app_destination.dart';
import '../../../core/navigation/app_navigator.dart';
import '../../../core/navigation/map_entry.dart';
import '../../../services/community_service.dart';
import '../../../services/hydro_dispatch_service.dart';
import '../../../services/location_service.dart';
import '../application/hydro_dispatch_controller.dart';
import 'hydro_dispatch_functional_dock.dart';

/// Functional bridge between the approved CHE page and the production P3/P4
/// Hydro Dispatch contracts.
///
/// The approved hydropower page remains the visual base. This bridge owns the
/// production utility wiring so the later pass can remain UI/UX polish only.
/// Community evidence is OBSERVED evidence, never official operator truth.
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
    if (state.isAlertMutationRunning || state.isLoading) return;
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

  void _openPremium() {
    AppNavigator.open<void>(context, AppDestination.premium);
  }

  void _openHydroSelector() {
    AppNavigator.open<void>(
      context,
      AppDestination.contextualMap,
      arguments: ContextualMapEntry.forTarget(
        source: 'hydro-dispatch-selector',
        target: const RuntimeMapCameraTarget(
          source: 'hydro-dispatch-selector',
          entityId: 'country-pack-ro',
          latitude: 45.9432,
          longitude: 24.9668,
          zoom: 5.65,
        ),
      ),
    );
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
    final accessTier = ref.watch(fluviAccessTierProvider);
    _bind(selected);
    final plantId = selected?.hydropowerPlantId?.trim();
    final state = ref.watch(hydroDispatchMobileProvider);

    if (plantId == null || plantId.isEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: FilledButton.icon(
                key: const ValueKey('hydro-dispatch-select-che'),
                onPressed: _openHydroSelector,
                icon: const Icon(Icons.map_rounded),
                label: Text(
                  _isRomanian
                      ? 'Selectează o CHE pe harta Hydro România'
                      : 'Select a plant on the Romania Hydro map',
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        HydroDispatchFunctionalDock(
          state: state,
          plantName:
              _boundPlantName ?? selected?.locationName ?? 'Hydro Dispatch',
          isRomanian: _isRomanian,
          isPremium: accessTier == FluviAccessTier.premium,
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
          onOpenPremium: _openPremium,
        ),
      ],
    );
  }
}
