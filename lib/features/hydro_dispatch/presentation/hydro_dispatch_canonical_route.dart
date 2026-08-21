import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../models/water_asset.dart';
import '../../../services/water_asset_service.dart';
import 'hydro_dispatch_route_bridge.dart';

/// Canonicalizes a hydropower route before Hydro Dispatch binds to it.
///
/// New map/runtime callers must pass the canonical [plant] so identity is never
/// downgraded to a display name. [plantLabel] remains only as a legacy/deep-link
/// fallback for routes that predate the canonical plant contract.
class HydroDispatchCanonicalRoute extends ConsumerStatefulWidget {
  const HydroDispatchCanonicalRoute({
    super.key,
    required this.child,
    this.plant,
    this.plantLabel,
    this.waterAssetService = const WaterAssetService(),
  });

  final Widget child;
  final WaterMapPin? plant;
  final String? plantLabel;
  final WaterAssetService waterAssetService;

  @override
  ConsumerState<HydroDispatchCanonicalRoute> createState() =>
      _HydroDispatchCanonicalRouteState();
}

class _HydroDispatchCanonicalRouteState
    extends ConsumerState<HydroDispatchCanonicalRoute> {
  String? _lastResolvedIdentity;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureCanonicalPlant(),
    );
  }

  @override
  void didUpdateWidget(covariant HydroDispatchCanonicalRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIdentity = oldWidget.plant?.entityId ?? oldWidget.plantLabel;
    final newIdentity = widget.plant?.entityId ?? widget.plantLabel;
    if (oldIdentity != newIdentity) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureCanonicalPlant(),
      );
    }
  }

  Future<void> _ensureCanonicalPlant() async {
    if (!mounted || _resolving) return;

    final canonicalPlant = widget.plant;
    if (canonicalPlant != null) {
      final plantId = canonicalPlant.entityId.trim();
      if (plantId.isEmpty) return;
      final selected = ref.read(selectedContextProvider);
      if (selected?.hydropowerPlantId?.trim() != plantId ||
          selected?.locationName != canonicalPlant.name) {
        ref
            .read(selectedContextProvider.notifier)
            .select(SelectedContext.fromHydropowerPin(canonicalPlant));
      }
      _lastResolvedIdentity = plantId;
      return;
    }

    final label = widget.plantLabel?.trim();
    if (label == null || label.isEmpty) return;

    final normalizedLabel = _normalizeHydropowerName(label);
    final selected = ref.read(selectedContextProvider);
    final selectedName = selected?.locationName?.trim();
    final selectedPlantId = selected?.hydropowerPlantId?.trim();
    if (selectedPlantId != null &&
        selectedPlantId.isNotEmpty &&
        selectedName != null &&
        _normalizeHydropowerName(selectedName) == normalizedLabel) {
      _lastResolvedIdentity = selectedPlantId;
      return;
    }
    if (_lastResolvedIdentity == normalizedLabel && selectedPlantId != null) {
      return;
    }

    _resolving = true;
    try {
      final candidates = await widget.waterAssetService.searchHydropower(
        label,
        limit: 16,
      );
      if (!mounted) return;
      final pin = _bestExactHydropowerMatch(candidates, label);
      if (pin == null) return;

      final current = ref.read(selectedContextProvider);
      if (current?.hydropowerPlantId?.trim() != pin.entityId) {
        ref
            .read(selectedContextProvider.notifier)
            .select(SelectedContext.fromHydropowerPin(pin));
      }
      _lastResolvedIdentity = pin.entityId;
    } on Exception {
      // No forecast is fabricated when legacy canonicalization cannot resolve.
    } finally {
      _resolving = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      HydroDispatchRouteBridge(child: widget.child);
}

WaterMapPin? _bestExactHydropowerMatch(
  List<WaterMapPin> candidates,
  String label,
) {
  if (candidates.isEmpty) return null;
  final target = _normalizeHydropowerName(label);
  for (final pin in candidates) {
    if (_normalizeHydropowerName(pin.name) == target) return pin;
  }
  return candidates.length == 1 ? candidates.first : null;
}

String _normalizeHydropowerName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ă', 'a')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('ș', 's')
    .replaceAll('ş', 's')
    .replaceAll('ț', 't')
    .replaceAll('ţ', 't');
