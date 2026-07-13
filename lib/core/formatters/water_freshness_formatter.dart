abstract final class WaterFreshnessFormatter {
  static String format({
    required DateTime measurementTimestamp,
    required DateTime now,
    required bool isStale,
    required String locale,
  }) {
    final measuredAge = now.difference(measurementTimestamp);
    final age = measuredAge.isNegative ? Duration.zero : measuredAge;
    final isRomanian = locale.toLowerCase().startsWith('ro');

    if (age.inMinutes < 1) {
      return isRomanian ? 'Acum' : 'Now';
    }

    final ageLabel = _elapsedUnitLabel(age, isRomanian: isRomanian);
    if (isStale) {
      return isRomanian ? 'Vechi \u2022 $ageLabel' : 'Stale \u2022 $ageLabel';
    }
    return isRomanian ? 'Acum $ageLabel' : '$ageLabel ago';
  }

  static String _elapsedUnitLabel(Duration age, {required bool isRomanian}) {
    if (age.inMinutes < 60) {
      final value = age.inMinutes;
      if (!isRomanian) {
        return '$value ${value == 1 ? 'minute' : 'minutes'}';
      }
      return '$value ${value == 1 ? 'minut' : 'minute'}';
    }
    if (age.inHours < 24) {
      final value = age.inHours;
      if (!isRomanian) return '$value ${value == 1 ? 'hour' : 'hours'}';
      return '$value ${value == 1 ? 'or\u0103' : 'ore'}';
    }
    final value = age.inDays;
    if (!isRomanian) return '$value ${value == 1 ? 'day' : 'days'}';
    return '$value ${value == 1 ? 'zi' : 'zile'}';
  }
}
