import 'dart:async';

/// One-shot navigation intent used when Hydro Map is opened specifically to
/// choose a CHE for Hydro Dispatch. General Map browsing never arms this.
typedef HydroDispatchPlantSelectionHandler =
    void Function(String plantId, String? plantName);

abstract final class HydroDispatchNavigationIntent {
  static Timer? _expiryTimer;
  static HydroDispatchPlantSelectionHandler? _handler;

  static bool get isArmed => _handler != null;

  static void arm({
    required HydroDispatchPlantSelectionHandler onSelected,
    Duration ttl = const Duration(minutes: 10),
  }) {
    _expiryTimer?.cancel();
    _handler = onSelected;
    _expiryTimer = Timer(ttl, disarm);
  }

  static void disarm() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _handler = null;
  }

  /// Consumes the intent exactly once. Any explicit non-hydropower selection
  /// cancels the selector intent so a later general-map CHE tap cannot open
  /// Hydro Dispatch unexpectedly.
  static void notifySelection({String? plantId, String? plantName}) {
    final handler = _handler;
    if (handler == null) return;

    final normalizedPlantId = plantId?.trim();
    if (normalizedPlantId == null || normalizedPlantId.isEmpty) {
      disarm();
      return;
    }

    final normalizedPlantName = plantName?.trim();
    disarm();
    handler(
      normalizedPlantId,
      normalizedPlantName == null || normalizedPlantName.isEmpty
          ? null
          : normalizedPlantName,
    );
  }
}