import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../services/community_service.dart';
import '../../../services/hydro_dispatch_service.dart';
import '../application/hydro_dispatch_controller.dart';

/// Invisible route bridge: it keeps the approved hydropower presentation
/// untouched while binding its selected CHE to the real P3/P4 mobile state.
///
/// While the CHE route remains mounted, it also observes the canonical report
/// stream. If the angler publishes a report from this CHE context, FluviAI can
/// optionally attach that same report to Hydro Dispatch as OBSERVED evidence.
/// A community observation never becomes official operator confirmation.
class HydroDispatchRouteBridge extends ConsumerStatefulWidget {
  const HydroDispatchRouteBridge({
    super.key,
    required this.child,
    this.communityService = const CommunityService(),
    this.hydroDispatchService = const HydroDispatchService(),
  });

  final Widget child;
  final CommunityService communityService;
  final HydroDispatchService hydroDispatchService;

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
        _boundPlantName ?? (Localizations.localeOf(context).languageCode == 'ro'
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
      unawaited(
        ref
            .read(hydroDispatchMobileProvider.notifier)
            .refresh(plantId, force: true),
      );
      final isRo =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRo
                ? 'Observația a fost legată de Hydro Dispatch ca dovadă OBSERVED, nu ca confirmare oficială.'
                : 'The observation was linked to Hydro Dispatch as OBSERVED evidence, not official confirmation.',
          ),
        ),
      );
    } on HydroDispatchException catch (error) {
      if (!mounted) return;
      final isRo =
          Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isRo
                ? 'Raportul a fost publicat, dar observația Hydro nu a putut fi legată: ${error.message}'
                : 'The report was published, but the Hydro observation could not be linked: ${error.message}',
          ),
        ),
      );
    } finally {
      _handlingReport = false;
    }
  }

  Future<String?> _chooseObservedEvent(String plantName) {
    final isRo =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ro';
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
              isRo
                  ? 'Ai observat o operațiune la $plantName?'
                  : 'Did you observe an operation at $plantName?',
            ),
            subtitle: Text(
              isRo
                  ? 'Opțional. Raportul este deja publicat. Observația comunitară nu este confirmare oficială a operatorului.'
                  : 'Optional. The report is already published. Community observation is not official operator confirmation.',
            ),
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_started',
            icon: Icons.play_circle_outline_rounded,
            label: isRo ? 'Uzinarea a început' : 'Generation started',
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_active',
            icon: Icons.bolt_rounded,
            label: isRo ? 'Uzinare activă acum' : 'Generation active now',
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_stopped',
            icon: Icons.stop_circle_outlined,
            label: isRo ? 'Uzinarea s-a oprit' : 'Generation stopped',
          ),
          _eventTile(
            sheetContext,
            value: 'release_observed',
            icon: Icons.waves_rounded,
            label: isRo ? 'Evacuare observată' : 'Release observed',
          ),
          _eventTile(
            sheetContext,
            value: 'spill_observed',
            icon: Icons.water_rounded,
            label: isRo ? 'Deversare observată' : 'Spill observed',
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(isRo ? 'Doar raport general' : 'General report only'),
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
    return widget.child;
  }
}
