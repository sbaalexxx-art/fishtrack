import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../application/hydro_dispatch_controller.dart';

/// Invisible route bridge: it keeps the approved hydropower presentation
/// untouched while binding its selected CHE to the real P3/P4 mobile state.
class HydroDispatchRouteBridge extends ConsumerStatefulWidget {
  const HydroDispatchRouteBridge({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<HydroDispatchRouteBridge> createState() =>
      _HydroDispatchRouteBridgeState();
}

class _HydroDispatchRouteBridgeState
    extends ConsumerState<HydroDispatchRouteBridge> {
  String? _boundPlantId;

  void _bind(String? plantId) {
    final normalized = plantId?.trim();
    if (normalized == null || normalized.isEmpty || normalized == _boundPlantId) {
      return;
    }
    _boundPlantId = normalized;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _boundPlantId != normalized) return;
      ref.read(hydroDispatchMobileProvider.notifier).refresh(normalized);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedContextProvider);
    _bind(selected?.hydropowerPlantId);
    return widget.child;
  }
}
