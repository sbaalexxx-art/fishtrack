import 'package:fishtrack/services/hydro_map_canonical_service.dart';
import 'package:fishtrack/services/hydro_map_dispatch_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presents safe Romanian dispatch probability and local window', () {
    final snapshot = HydroMapDispatchSnapshot.fromJson(<String, dynamic>{
      'plant_id': 'plant-1',
      'name': 'Draganesti',
      'availability_status': 'AVAILABLE',
      'window_start': '2026-08-21T13:30:00Z',
      'window_end': '2026-08-21T20:00:00Z',
      'window_probability': 0.6834,
      'confidence': 'low',
      'evidence_class': 'ESTIMATED',
      'observed_state': 'NO_RECENT_OBSERVATION',
      'observed_freshness': 'unavailable',
      'observed_report_count': 0,
    });

    final presentation = HydroMapDispatchPresenter.present(
      snapshot,
      isRomanian: true,
    );

    expect(presentation.available, isTrue);
    expect(presentation.title, 'Probabilitate uzinare');
    expect(presentation.probabilityLabel, '68.3%');
    expect(presentation.windowLabel, '16:30–23:00');
    expect(presentation.confidenceLabel, 'încredere redusă');
    expect(presentation.evidenceLabel, 'ESTIMATED');
  });

  test('never invents probability when dispatch is unavailable', () {
    final snapshot = HydroMapDispatchSnapshot.fromJson(<String, dynamic>{
      'plant_id': 'plant-2',
      'name': 'Calimanesti',
      'availability_status': 'UNAVAILABLE',
      'confidence': 'unknown',
      'evidence_class': 'UNKNOWN',
      'observed_state': 'NO_RECENT_OBSERVATION',
      'observed_freshness': 'unavailable',
      'observed_report_count': 0,
    });

    final presentation = HydroMapDispatchPresenter.present(
      snapshot,
      isRomanian: true,
    );

    expect(presentation.available, isFalse);
    expect(presentation.probabilityLabel, '—');
    expect(presentation.windowLabel, '—');
  });
}
