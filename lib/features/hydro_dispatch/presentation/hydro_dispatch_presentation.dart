import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../../services/hydro_dispatch_service.dart';

class HydroDispatchDayPresentation {
  const HydroDispatchDayPresentation({
    required this.dayLabel,
    required this.statusLabel,
    required this.probabilityLabel,
    required this.windowLabel,
    required this.evidenceLabel,
    required this.confidenceLabel,
    required this.available,
  });

  final String dayLabel;
  final String statusLabel;
  final String probabilityLabel;
  final String windowLabel;
  final String evidenceLabel;
  final String confidenceLabel;
  final bool available;
}

abstract final class HydroDispatchPresentation {
  static bool _timezoneReady = false;

  static HydroDispatchDayPresentation day(
    HydroDispatchDayForecast? forecast, {
    required bool isRomanian,
  }) {
    final dayLabel = forecast?.dayOffset == 1
        ? (isRomanian ? 'Mâine' : 'Tomorrow')
        : (isRomanian ? 'Azi' : 'Today');

    if (forecast == null) {
      return HydroDispatchDayPresentation(
        dayLabel: dayLabel,
        statusLabel: isRomanian ? 'Date indisponibile' : 'Data unavailable',
        probabilityLabel: '—',
        windowLabel: '—',
        evidenceLabel: 'UNKNOWN',
        confidenceLabel: isRomanian
            ? 'încredere necunoscută'
            : 'unknown confidence',
        available: false,
      );
    }

    if (!forecast.isAvailable) {
      final notPublished = forecast.availabilityStatus == 'NOT_YET_PUBLISHED';
      return HydroDispatchDayPresentation(
        dayLabel: dayLabel,
        statusLabel: notPublished
            ? (isRomanian ? 'Încă nepublicat' : 'Not published yet')
            : (isRomanian ? 'Date indisponibile' : 'Data unavailable'),
        probabilityLabel: '—',
        windowLabel: '—',
        evidenceLabel: forecast.evidenceClass,
        confidenceLabel: _confidence(forecast.confidence, isRomanian),
        available: false,
      );
    }

    return HydroDispatchDayPresentation(
      dayLabel: dayLabel,
      statusLabel: isRomanian
          ? 'Probabilitate uzinare'
          : 'Generation probability',
      probabilityLabel: _percent(forecast.windowProbability),
      windowLabel:
          '${_romaniaTime(forecast.windowStart)}–${_romaniaTime(forecast.windowEnd)}',
      evidenceLabel: forecast.evidenceClass,
      confidenceLabel: _confidence(forecast.confidence, isRomanian),
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
