import 'package:fishtrack/services/water_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WaterAlert alert(String id) => WaterAlert(
    id: id,
    stationId: 'station-1',
    stationName: 'Test Station',
    type: WaterAlertType.rapidChange,
    timestamp: DateTime.utc(2026, 7, 6),
  );

  test('history prevents duplicate alert ids', () {
    final history = MemoryWaterAlertHistoryStore();

    history.add(alert('event-1'));
    history.add(alert('event-1'));

    expect(history.alerts, hasLength(1));
  });

  test('history is bounded and supports read state', () {
    final history = MemoryWaterAlertHistoryStore(maximumAlerts: 2);

    history.add(alert('event-1'));
    history.add(alert('event-2'));
    history.markRead('event-2');
    history.add(alert('event-3'));

    expect(history.alerts, hasLength(2));
    expect(history.alerts.first.id, 'event-3');
    expect(history.alerts.last.isRead, isTrue);
  });
}
