import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'hydro_map_canonical_service.dart';

class HydroMapDispatchPresentation {
  const HydroMapDispatchPresentation({
    required this.available,
    required this.title,
    required this.probabilityLabel,
    required this.windowLabel,
    required this.confidenceLabel,
    required this.evidenceLabel,
  });

  final bool available;
  final String title;
  final String probabilityLabel;
  final String windowLabel;
  final String confidenceLabel;
  final String evidenceLabel;
}

abstract final class HydroMapDispatchPresenter {
  static bool _timezoneReady = false;

  static HydroMapDispatchPresentation present(
    HydroMapDispatchSnapshot? snapshot, {
    required bool isRomanian,
  }) {
    if (snapshot == null || !snapshot.isAvailable) {
      return HydroMapDispatchPresentation(
        available: false,
        title: isRomanian ? 'Probabilitate uzinare' : 'Generation probability',
        probabilityLabel: '—',
        windowLabel: '—',
        confidenceLabel: _confidence(
          snapshot?.confidence ?? 'unknown',
          isRomanian,
        ),
        evidenceLabel: snapshot?.evidenceClass ?? 'UNKNOWN',
      );
    }

    return HydroMapDispatchPresentation(
      available: true,
      title: isRomanian ? 'Probabilitate uzinare' : 'Generation probability',
      probabilityLabel: _percent(snapshot.windowProbability),
      windowLabel:
          '${_romaniaTime(snapshot.windowStart)}–${_romaniaTime(snapshot.windowEnd)}',
      confidenceLabel: _confidence(snapshot.confidence, isRomanian),
      evidenceLabel: snapshot.evidenceClass,
    );
  }

  static String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)}%';

  static String _romaniaTime(DateTime? value) {
    if (value == null) return '—';
    if (!_timezoneReady) {
      timezone_data.initializeTimeZones();
      _timezoneReady = true;
    }
    final location = timezone.getLocation('Europe/Bucharest');
    final local = timezone.TZDateTime.from(value.toUtc(), location);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _confidence(String value, bool ro) => switch (value
      .toLowerCase()) {
    'high' => ro ? 'încredere ridicată' : 'high confidence',
    'medium' || 'moderate' => ro ? 'încredere moderată' : 'moderate confidence',
    'low' => ro ? 'încredere redusă' : 'low confidence',
    _ => ro ? 'încredere necunoscută' : 'unknown confidence',
  };
}
