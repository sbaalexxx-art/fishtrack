import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../../services/hydro_dispatch_service.dart';

class HydroDispatchDayPresentation {
  const HydroDispatchDayPresentation({
    required this.dayLabel,
    required this.dateLabel,
    required this.statusLabel,
    required this.probabilityLabel,
    required this.windowLabel,
    required this.evidenceLabel,
    required this.confidenceLabel,
    required this.freshnessLabel,
    required this.available,
  });

  final String dayLabel;
  final String dateLabel;
  final String statusLabel;
  final String probabilityLabel;
  final String windowLabel;
  final String evidenceLabel;
  final String confidenceLabel;
  final String freshnessLabel;
  final bool available;
}

abstract final class HydroDispatchPresentation {
  static bool _timezoneReady = false;

  /// Presents one explicit delivery day. [fallbackDayOffset] is mandatory for
  /// callers that may pass a null forecast so an unavailable Tomorrow can
  /// never be mislabeled as Today.
  static HydroDispatchDayPresentation day(
    HydroDispatchDayForecast? forecast, {
    required bool isRomanian,
    int fallbackDayOffset = 0,
  }) {
    final dayOffset = forecast?.dayOffset ?? fallbackDayOffset;
    final dayLabel = dayOffset == 1
        ? (isRomanian ? 'Mâine' : 'Tomorrow')
        : (isRomanian ? 'Azi' : 'Today');
    final deliveryDate = forecast?.deliveryDate ?? _deliveryDate(dayOffset);
    final dateLabel = _dateLabel(deliveryDate);
    final freshnessLabel = _freshness(
      forecast?.updatedAt,
      isRomanian: isRomanian,
    );

    if (forecast == null) {
      return HydroDispatchDayPresentation(
        dayLabel: dayLabel,
        dateLabel: dateLabel,
        statusLabel: isRomanian ? 'Date indisponibile' : 'Data unavailable',
        probabilityLabel: '—',
        windowLabel: '—',
        evidenceLabel: 'UNKNOWN',
        confidenceLabel: isRomanian
            ? 'încredere necunoscută'
            : 'unknown confidence',
        freshnessLabel: freshnessLabel,
        available: false,
      );
    }

    if (!forecast.isAvailable) {
      final notPublished = forecast.availabilityStatus == 'NOT_YET_PUBLISHED';
      return HydroDispatchDayPresentation(
        dayLabel: dayLabel,
        dateLabel: dateLabel,
        statusLabel: notPublished
            ? (isRomanian ? 'În așteptarea publicării' : 'Awaiting publication')
            : (isRomanian ? 'Date indisponibile' : 'Data unavailable'),
        probabilityLabel: '—',
        windowLabel: '—',
        evidenceLabel: forecast.evidenceClass,
        confidenceLabel: _confidence(forecast.confidence, isRomanian),
        freshnessLabel: freshnessLabel,
        available: false,
      );
    }

    return HydroDispatchDayPresentation(
      dayLabel: dayLabel,
      dateLabel: dateLabel,
      statusLabel: isRomanian
          ? 'Probabilitate uzinare'
          : 'Generation probability',
      probabilityLabel: _percent(forecast.windowProbability),
      windowLabel:
          '${_romaniaTime(forecast.windowStart)}–${_romaniaTime(forecast.windowEnd)}',
      evidenceLabel: forecast.evidenceClass,
      confidenceLabel: _confidence(forecast.confidence, isRomanian),
      freshnessLabel: freshnessLabel,
      available: true,
    );
  }

  static HydroDispatchDayPresentation mapSnapshot(
    HydroMapDispatchSnapshot? snapshot, {
    required bool isRomanian,
  }) {
    final date = _deliveryDate(0);
    if (snapshot == null || !snapshot.isAvailable) {
      return HydroDispatchDayPresentation(
        dayLabel: isRomanian ? 'Azi' : 'Today',
        dateLabel: _dateLabel(date),
        statusLabel: isRomanian ? 'Date indisponibile' : 'Data unavailable',
        probabilityLabel: '—',
        windowLabel: '—',
        evidenceLabel: snapshot?.evidenceClass ?? 'UNKNOWN',
        confidenceLabel: _confidence(
          snapshot?.confidence ?? 'unknown',
          isRomanian,
        ),
        freshnessLabel: _freshness(
          snapshot?.updatedAt,
          isRomanian: isRomanian,
        ),
        available: false,
      );
    }
    return HydroDispatchDayPresentation(
      dayLabel: isRomanian ? 'Azi' : 'Today',
      dateLabel: _dateLabel(date),
      statusLabel: isRomanian
          ? 'Probabilitate uzinare'
          : 'Generation probability',
      probabilityLabel: _percent(snapshot.windowProbability),
      windowLabel:
          '${_romaniaTime(snapshot.windowStart)}–${_romaniaTime(snapshot.windowEnd)}',
      evidenceLabel: snapshot.evidenceClass,
      confidenceLabel: _confidence(snapshot.confidence, isRomanian),
      freshnessLabel: _freshness(
        snapshot.updatedAt,
        isRomanian: isRomanian,
      ),
      available: true,
    );
  }

  static String aiExplanation(
    HydroDispatchAiContext? context, {
    required bool isRomanian,
  }) {
    if (context == null) {
      return isRomanian
          ? 'Contextul Hydro Dispatch nu este disponibil.'
          : 'Hydro Dispatch context is unavailable.';
    }

    final parts = <String>[];
    final probability = context.probability;
    if (probability != null) {
      parts.add(
        isRomanian
            ? 'Probabilitate ${_percent(probability)} (${_band(context.probabilityBand, true)}).'
            : '${_percent(probability)} probability (${_band(context.probabilityBand, false)}).',
      );
    }

    parts.add(
      isRomanian
          ? 'Semnal sistem: ${_systemSignal(context.systemSignalStatus, true)}.'
          : 'System signal: ${_systemSignal(context.systemSignalStatus, false)}.',
    );
    parts.add(
      isRomanian
          ? 'Tendință hidro națională: ${_hydroTrend(context.hydroTrend, true)}.'
          : 'National hydro trend: ${_hydroTrend(context.hydroTrend, false)}.',
    );
    parts.add(
      isRomanian
          ? 'Semnal local ploaie: ${_rain(context.localRainSignal, true)}.'
          : 'Local rain signal: ${_rain(context.localRainSignal, false)}.',
    );

    if (context.observedState == 'OBSERVED_ACTIVE') {
      parts.add(
        isRomanian
            ? 'Există uzinare observată în teren de comunitate.'
            : 'Community field evidence reports active generation.',
      );
    } else if (context.observedState == 'OBSERVED_ENDED') {
      parts.add(
        isRomanian
            ? 'Există o oprire observată în teren de comunitate.'
            : 'Community field evidence reports generation ended.',
      );
    }

    if (context.calibrationSampleCount > 0) {
      parts.add(
        isRomanian
            ? 'Calibrare: ${context.calibrationSampleCount} observații eligibile.'
            : 'Calibration: ${context.calibrationSampleCount} eligible observations.',
      );
    } else {
      parts.add(
        isRomanian
            ? 'Modelul nu are încă suficiente confirmări de teren pentru calibrare statistică.'
            : 'The model does not yet have enough field confirmations for statistical calibration.',
      );
    }

    parts.add(
      isRomanian
          ? 'Estimarea nu reprezintă confirmare oficială a operatorului.'
          : 'The estimate is not official operator confirmation.',
    );
    return parts.join(' ');
  }

  static String observedLabel(
    HydroDispatchAiContext? context, {
    required bool isRomanian,
  }) => switch (context?.observedState) {
    'OBSERVED_ACTIVE' =>
      isRomanian
          ? 'UZINARE OBSERVATĂ ÎN TEREN'
          : 'GENERATION OBSERVED IN THE FIELD',
    'OBSERVED_RECENT' =>
      isRomanian ? 'OBSERVAȚIE RECENTĂ ÎN TEREN' : 'RECENT FIELD OBSERVATION',
    'OBSERVED_ENDED' =>
      isRomanian
          ? 'OPRIRE OBSERVATĂ ÎN TEREN'
          : 'GENERATION END OBSERVED IN FIELD',
    _ => isRomanian ? 'FĂRĂ OBSERVAȚIE RECENTĂ' : 'NO RECENT FIELD OBSERVATION',
  };

  static String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)}%';

  static timezone.Location _romaniaLocation() {
    if (!_timezoneReady) {
      timezone_data.initializeTimeZones();
      _timezoneReady = true;
    }
    return timezone.getLocation('Europe/Bucharest');
  }

  static DateTime _deliveryDate(int dayOffset) {
    final now = timezone.TZDateTime.now(_romaniaLocation());
    return timezone.TZDateTime(
      _romaniaLocation(),
      now.year,
      now.month,
      now.day + dayOffset,
    );
  }

  static String _romaniaTime(DateTime? value) {
    if (value == null) return '—';
    final local = timezone.TZDateTime.from(value.toUtc(), _romaniaLocation());
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _dateLabel(DateTime value) {
    final local = value is timezone.TZDateTime
        ? value
        : timezone.TZDateTime.from(value.toUtc(), _romaniaLocation());
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  static String _freshness(
    DateTime? updatedAt, {
    required bool isRomanian,
  }) {
    if (updatedAt == null) {
      return isRomanian ? 'actualizare indisponibilă' : 'update unavailable';
    }
    return '${isRomanian ? 'actualizat' : 'updated'} ${_romaniaTime(updatedAt)}';
  }

  static String _confidence(String value, bool ro) => switch (value
      .toLowerCase()) {
    'high' => ro ? 'încredere ridicată' : 'high confidence',
    'medium' || 'moderate' => ro ? 'încredere moderată' : 'moderate confidence',
    'low' => ro ? 'încredere redusă' : 'low confidence',
    _ => ro ? 'încredere necunoscută' : 'unknown confidence',
  };

  static String _band(String value, bool ro) => switch (value.toLowerCase()) {
    'low' => ro ? 'redusă' : 'low',
    'moderate' => ro ? 'posibilă' : 'possible',
    'high' => ro ? 'ridicată' : 'high',
    'very_high' => ro ? 'foarte ridicată' : 'very high',
    _ => ro ? 'necunoscută' : 'unknown',
  };

  static String _systemSignal(String value, bool ro) =>
      switch (value.toLowerCase()) {
        'fresh' => ro ? 'actual' : 'fresh',
        'stale' => ro ? 'vechi' : 'stale',
        'unavailable' => ro ? 'indisponibil' : 'unavailable',
        _ => value.replaceAll('_', ' '),
      };

  static String _hydroTrend(String value, bool ro) =>
      switch (value.toLowerCase()) {
        'rising' => ro ? 'în creștere' : 'rising',
        'falling' => ro ? 'în scădere' : 'falling',
        'stable' => ro ? 'stabilă' : 'stable',
        'unavailable' => ro ? 'indisponibilă' : 'unavailable',
        _ => value.replaceAll('_', ' '),
      };

  static String _rain(String value, bool ro) => switch (value.toLowerCase()) {
    'dry' => ro ? 'scăzut/uscat' : 'low/dry',
    'wet' => ro ? 'umed' : 'wet',
    'heavy' => ro ? 'ridicat' : 'high',
    'unknown' || 'unavailable' => ro ? 'indisponibil' : 'unavailable',
    _ => value.replaceAll('_', ' '),
  };
}
