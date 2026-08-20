import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/context/selected_context.dart';
import '../../../models/water_asset.dart';
import '../../../services/water_asset_service.dart';
import 'hydro_dispatch_route_bridge.dart';

/// Canonicalizes a hydropower route before Hydro Dispatch binds to it.
///
/// Some legacy/map entry points only carry the CHE display name. Hydro Dispatch
/// requires the canonical `plant_id`, so this route resolves the real CHE from
/// the Water catalog and synchronizes [selectedContextProvider]. No forecast is
/// fabricated and no name is converted to a hard-coded id.
class HydroDispatchCanonicalRoute extends ConsumerStatefulWidget {
  const HydroDispatchCanonicalRoute({
    super.key,
    required this.child,
    this.plantLabel,
    this.waterAssetService = const WaterAssetService(),
  });

  final Widget child;
  final String? plantLabel;
  final WaterAssetService waterAssetService;

  @override
  ConsumerState<HydroDispatchCanonicalRoute> createState() =>
      _HydroDispatchCanonicalRouteState();
}

class _HydroDispatchCanonicalRouteState
    extends ConsumerState<HydroDispatchCanonicalRoute> {
  String? _lastResolvedLabel;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCanonicalPlant());
  }

  @override
  void didUpdateWidget(covariant HydroDispatchCanonicalRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plantLabel != widget.plantLabel) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCanonicalPlant());
    }
  }

  Future<void> _ensureCanonicalPlant() async {
    if (!mounted || _resolving) return;
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
      _lastResolvedLabel = normalizedLabel;
      return;
    }
    if (_lastResolvedLabel == normalizedLabel && selectedPlantId != null) return;

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
      if (current?.hydropowerPlantId?.trim() == pin.entityId) {
        _lastResolvedLabel = normalizedLabel;
        return;
      }

      ref
          .read(selectedContextProvider.notifier)
          .select(SelectedContext.fromHydropowerPin(pin));
      _lastResolvedLabel = normalizedLabel;
    } on Exception {
      // The child remains truthful and usable even if canonicalization cannot
      // resolve. Hydro Dispatch will not display a forecast without a real id.
    } finally {
      _resolving = false;
    }
  }

  @override
  Widget build(BuildContext context) => HydroDispatchRouteBridge(
    child: widget.child,
  );
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
