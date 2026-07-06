import 'package:fishtrack/services/astronomy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = AstronomyService();

  test('known new moon has near-zero age and illumination', () {
    final moon = service.moonPhase(DateTime.utc(2000, 1, 6, 18, 14));

    expect(moon.name, 'New Moon');
    expect(moon.ageDays, closeTo(0, 0.001));
    expect(moon.illuminationPercent, closeTo(0, 0.001));
  });

  test('quarter-cycle dates produce waxing and full phases', () {
    final firstQuarter = service.moonPhase(DateTime.utc(2000, 1, 14, 3, 25));
    final fullMoon = service.moonPhase(DateTime.utc(2000, 1, 21, 12));

    expect(firstQuarter.name, 'First Quarter');
    expect(firstQuarter.illuminationPercent, closeTo(50, 4));
    expect(fullMoon.name, 'Full Moon');
    expect(fullMoon.illuminationPercent, greaterThan(97));
  });

  test('golden hours are ordered around sunrise and sunset', () {
    final result = service.calculate(
      dateTime: DateTime(2026, 7, 6, 12),
      latitude: 44.43,
      longitude: 26.10,
    );
    final golden = result.goldenHour!;

    expect(result.availability, AstronomyAvailability.available);
    expect(golden.morningEnd.difference(golden.morningStart).inMinutes, 60);
    expect(golden.eveningEnd.difference(golden.eveningStart).inMinutes, 60);
    expect(golden.eveningStart.isAfter(golden.morningEnd), isTrue);
  });
}
