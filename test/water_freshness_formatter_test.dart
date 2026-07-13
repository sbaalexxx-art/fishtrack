import 'package:fishtrack/core/formatters/water_freshness_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 13, 12);

  String format(Duration age, {String locale = 'ro', bool isStale = false}) =>
      WaterFreshnessFormatter.format(
        measurementTimestamp: now.subtract(age),
        now: now,
        isStale: isStale,
        locale: locale,
      );

  test('under one minute is now', () {
    expect(format(const Duration(seconds: 59)), 'Acum');
    expect(format(const Duration(seconds: 59), locale: 'en'), 'Now');
  });

  test('formats elapsed minutes', () {
    expect(format(const Duration(minutes: 15)), 'Acum 15 minute');
    expect(format(const Duration(minutes: 15), locale: 'en'), '15 minutes ago');
  });

  test('keeps 59 minutes in the minute unit', () {
    expect(format(const Duration(minutes: 59)), 'Acum 59 minute');
    expect(format(const Duration(minutes: 59), locale: 'en'), '59 minutes ago');
  });

  test('uses only complete hours at one hour and 59 minutes', () {
    expect(format(const Duration(hours: 1, minutes: 59)), 'Acum 1 or\u0103');
    expect(
      format(const Duration(hours: 1, minutes: 59), locale: 'en'),
      '1 hour ago',
    );
  });

  test('keeps 23 hours and 59 minutes in the hour unit', () {
    expect(format(const Duration(hours: 23, minutes: 59)), 'Acum 23 ore');
    expect(
      format(const Duration(hours: 23, minutes: 59), locale: 'en'),
      '23 hours ago',
    );
  });

  test('switches to days at one complete day', () {
    expect(format(const Duration(days: 1)), 'Acum 1 zi');
    expect(format(const Duration(days: 1), locale: 'en'), '1 day ago');
  });

  test('stale state keeps the complete elapsed unit', () {
    expect(
      format(const Duration(days: 2, hours: 23), isStale: true),
      'Vechi \u2022 2 zile',
    );
    expect(
      format(const Duration(days: 2, hours: 23), locale: 'en', isStale: true),
      'Stale \u2022 2 days',
    );
  });
}
