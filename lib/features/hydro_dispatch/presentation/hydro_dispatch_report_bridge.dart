import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../services/community_service.dart';
import '../../../services/hydro_dispatch_service.dart';
import '../application/hydro_dispatch_controller.dart';

/// Reuses the canonical Community report flow for optional Hydro Dispatch
/// observations. A normal report is always published first and remains valid
/// even if the optional Hydro association is skipped or fails.
///
/// This bridge never turns a community report into official operator data.
/// The backend records the optional association as OBSERVED evidence only.
class HydroDispatchReportBridge extends ConsumerStatefulWidget {
  const HydroDispatchReportBridge({
    super.key,
    required this.child,
    this.communityService = const CommunityService(),
    this.hydroDispatchService = const HydroDispatchService(),
  });

  final Widget child;
  final CommunityService communityService;
  final HydroDispatchService hydroDispatchService;

  @override
  ConsumerState<HydroDispatchReportBridge> createState() =>
      _HydroDispatchReportBridgeState();
}

class _HydroDispatchReportBridgeState
    extends ConsumerState<HydroDispatchReportBridge> {
  StreamSubscription<CommunityReportEvent>? _subscription;
  bool _handlingCreatedReport = false;
  final Set<String> _handledReportIds = <String>{};

  @override
  void initState() {
    super.initState();
    _subscription = widget.communityService.reportEvents.listen(_onReportEvent);
  }

  Future<void> _onReportEvent(CommunityReportEvent event) async {
    if (!mounted ||
        event.type != CommunityReportEventType.created ||
        _handlingCreatedReport ||
        _handledReportIds.contains(event.reportId)) {
      return;
    }

    final selected = ref.read(selectedContextProvider);
    final plantId = selected?.hydropowerPlantId?.trim();
    if (plantId == null || plantId.isEmpty) return;

    _handledReportIds.add(event.reportId);
    _handlingCreatedReport = true;
    try {
      final eventType = await _chooseObservedEvent(
        selected?.locationName ?? selected?.primaryLabel ?? 'CHE',
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Observația a fost legată de Hydro Dispatch ca dovadă OBSERVED, nu ca confirmare oficială.',
          ),
        ),
      );
    } on HydroDispatchException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Raportul a fost publicat, dar observația Hydro nu a putut fi legată: ${error.message}',
          ),
        ),
      );
    } finally {
      _handlingCreatedReport = false;
    }
  }

  Future<String?> _chooseObservedEvent(String plantName) {
    final isRomanian =
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
              isRomanian
                  ? 'Ai observat o operațiune la $plantName?'
                  : 'Did you observe an operation at $plantName?',
            ),
            subtitle: Text(
              isRomanian
                  ? 'Opțional. Raportul este deja publicat. Observația comunitară nu este confirmare oficială a operatorului.'
                  : 'Optional. The report is already published. Community observation is not official operator confirmation.',
            ),
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_started',
            icon: Icons.play_circle_outline_rounded,
            label: isRomanian ? 'Uzinarea a început' : 'Generation started',
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_active',
            icon: Icons.bolt_rounded,
            label: isRomanian ? 'Uzinare activă acum' : 'Generation active now',
          ),
          _eventTile(
            sheetContext,
            value: 'turbining_stopped',
            icon: Icons.stop_circle_outlined,
            label: isRomanian ? 'Uzinarea s-a oprit' : 'Generation stopped',
          ),
          _eventTile(
            sheetContext,
            value: 'release_observed',
            icon: Icons.waves_rounded,
            label: isRomanian ? 'Evacuare observată' : 'Release observed',
          ),
          _eventTile(
            sheetContext,
            value: 'spill_observed',
            icon: Icons.water_rounded,
            label: isRomanian ? 'Deversare observată' : 'Spill observed',
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(
              isRomanian ? 'Doar raport general' : 'General report only',
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
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
