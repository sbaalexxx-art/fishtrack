import 'dart:math' as math;

enum AstronomyAvailability { available, locationRequired, notAvailable }

class MoonPhaseData {
  const MoonPhaseData({
    required this.name,
    required this.illuminationPercent,
    required this.ageDays,
  });

  final String name;
  final double illuminationPercent;
  final double ageDays;
}

class GoldenHourData {
  const GoldenHourData({
    required this.morningStart,
    required this.morningEnd,
    required this.eveningStart,
    required this.eveningEnd,
  });

  final DateTime morningStart;
  final DateTime morningEnd;
  final DateTime eveningStart;
  final DateTime eveningEnd;

  bool contains(DateTime time) {
    final local = time.toLocal();
    return (!local.isBefore(morningStart) && !local.isAfter(morningEnd)) ||
        (!local.isBefore(eveningStart) && !local.isAfter(eveningEnd));
  }
}

class AstronomyContext {
  const AstronomyContext({
    required this.availability,
    required this.moon,
    this.goldenHour,
  });

  const AstronomyContext.locationRequired({required this.moon})
    : availability = AstronomyAvailability.locationRequired,
      goldenHour = null;

  const AstronomyContext.notAvailable({required this.moon})
    : availability = AstronomyAvailability.notAvailable,
      goldenHour = null;

  final AstronomyAvailability availability;
  final MoonPhaseData moon;
  final GoldenHourData? goldenHour;
}

class AstronomyService {
  const AstronomyService();

  static const _synodicMonth = 29.53058867;
  static final DateTime _knownNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

  MoonPhaseData moonPhase(DateTime dateTime) {
    final elapsedDays =
        dateTime.toUtc().difference(_knownNewMoon).inMilliseconds /
        Duration.millisecondsPerDay;
    final age = ((elapsedDays % _synodicMonth) + _synodicMonth) % _synodicMonth;
    final cycle = age / _synodicMonth;
    final illumination = (1 - math.cos(2 * math.pi * cycle)) / 2 * 100;
    final index = ((cycle * 8) + 0.5).floor() % 8;
    const names = [
      'New Moon',
      'Waxing Crescent',
      'First Quarter',
      'Waxing Gibbous',
      'Full Moon',
      'Waning Gibbous',
      'Last Quarter',
      'Waning Crescent',
    ];
    return MoonPhaseData(
      name: names[index],
      illuminationPercent: illumination.clamp(0, 100),
      ageDays: age,
    );
  }

  AstronomyContext calculate({
    required DateTime dateTime,
    required double latitude,
    required double longitude,
  }) {
    final moon = moonPhase(dateTime);
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return AstronomyContext.notAvailable(moon: moon);
    }
    final sunrise = _solarEvent(dateTime, latitude, longitude, sunrise: true);
    final sunset = _solarEvent(dateTime, latitude, longitude, sunrise: false);
    if (sunrise == null || sunset == null || !sunset.isAfter(sunrise)) {
      return AstronomyContext.notAvailable(moon: moon);
    }
    return AstronomyContext(
      availability: AstronomyAvailability.available,
      moon: moon,
      goldenHour: GoldenHourData(
        morningStart: sunrise,
        morningEnd: sunrise.add(const Duration(hours: 1)),
        eveningStart: sunset.subtract(const Duration(hours: 1)),
        eveningEnd: sunset,
      ),
    );
  }

  DateTime? _solarEvent(
    DateTime date,
    double latitude,
    double longitude, {
    required bool sunrise,
  }) {
    final day = _dayOfYear(date);
    final longitudeHour = longitude / 15;
    final approximateTime = day + ((sunrise ? 6 : 18) - longitudeHour) / 24;
    final meanAnomaly = 0.9856 * approximateTime - 3.289;
    var trueLongitude =
        meanAnomaly +
        1.916 * math.sin(_radians(meanAnomaly)) +
        0.020 * math.sin(_radians(2 * meanAnomaly)) +
        282.634;
    trueLongitude = _normalize(trueLongitude, 360);
    var rightAscension = _degrees(
      math.atan(0.91764 * math.tan(_radians(trueLongitude))),
    );
    rightAscension = _normalize(rightAscension, 360);
    rightAscension +=
        (trueLongitude / 90).floor() * 90 - (rightAscension / 90).floor() * 90;
    rightAscension /= 15;

    final sinDeclination = 0.39782 * math.sin(_radians(trueLongitude));
    final cosDeclination = math.cos(math.asin(sinDeclination));
    final cosHourAngle =
        (math.cos(_radians(90.833)) -
            sinDeclination * math.sin(_radians(latitude))) /
        (cosDeclination * math.cos(_radians(latitude)));
    if (cosHourAngle < -1 || cosHourAngle > 1) return null;
    var hourAngle = _degrees(math.acos(cosHourAngle));
    if (sunrise) hourAngle = 360 - hourAngle;
    hourAngle /= 15;
    final localMeanTime =
        hourAngle + rightAscension - 0.06571 * approximateTime - 6.622;
    final utcHours = _normalize(localMeanTime - longitudeHour, 24);
    final utcMidnight = DateTime.utc(date.year, date.month, date.day);
    return utcMidnight
        .add(Duration(seconds: (utcHours * 3600).round()))
        .toLocal();
  }

  static int _dayOfYear(DateTime date) =>
      date.difference(DateTime(date.year)).inDays + 1;
  static double _radians(double degrees) => degrees * math.pi / 180;
  static double _degrees(double radians) => radians * 180 / math.pi;
  static double _normalize(double value, double maximum) =>
      ((value % maximum) + maximum) % maximum;
}
