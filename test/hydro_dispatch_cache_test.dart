import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'package:fishtrack/features/hydro_dispatch/application/hydro_dispatch_cache.dart';
import 'package:fishtrack/services/hydro_dispatch_service.dart';

void main() {
  const plantId = '11111111-1111-1111-1111-111111111111';
  const cacheKey = 'hydro_dispatch_mobile_cache_v1_$plantId';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    timezone_data.initializeTimeZones();
  });

  HydroDispatchDayForecast forecastForToday() {
    final ro = timezone.getLocation('Europe/Bucharest');
    final now = timezone.TZDateTime.now(ro);
    final deliveryDate = DateTime(now.year, now.month, now.day);
    return HydroDispatchDayForecast(
      nodeOrder: 13,
      plantId: plantId,
      plantName: 'Frunzaru',
      deliveryDate: deliveryDate,
      dayOffset: 0,
      availabilityStatus: 'AVAILABLE',
      confidence: 'low',
      evidenceClass: 'ESTIMATED',
      systemSignalStatus: 'fresh',
      hydroTrend: 'falling',
      corroborationStatus: 'partial',
      localHydrologyStatus: 'available',
      localRainSignal: 'dry',
      localTargetCount: 5,
      windowStart: DateTime.now().toUtc().add(const Duration(hours: 1)),
      windowEnd: DateTime.now().toUtc().add(const Duration(hours: 5)),
      windowProbability: .66,
      peakProbability: .75,
      modelVersion: 'beta-test',
      updatedAt: DateTime.now().toUtc(),
    );
  }

  HydroDispatchAiContext aiForToday() => HydroDispatchAiContext(
    plantId: plantId,
    plantName: 'Frunzaru',
    dayOffset: 0,
    availabilityStatus: 'AVAILABLE',
    probabilityBand: 'moderate',
    confidence: 'low',
    evidenceClass: 'ESTIMATED',
    systemSignalStatus: 'fresh',
    hydroTrend: 'falling',
    localHydrologyStatus: 'available',
    localRainSignal: 'dry',
    observedState: 'NO_RECENT_OBSERVATION',
    observedFreshnessStatus: 'unavailable',
    calibrationStatus: 'insufficient_data',
    calibrationSampleCount: 0,
    truthDisclaimer: 'Estimate only.',
    probability: .66,
    peakProbability: .75,
  );

  test('restores only sanitized same-day mobile contract', () async {
    const cache = HydroDispatchCache();
    await cache.save(
      plantId: plantId,
      forecasts: <HydroDispatchDayForecast>[forecastForToday()],
      aiContext: <HydroDispatchAiContext>[aiForToday()],
    );

    final restored = await cache.restore(plantId);
    expect(restored, isNotNull);
    expect(restored!.forecasts.single.plantName, 'Frunzaru');
    expect(restored.forecasts.single.windowProbability, closeTo(.66, .000001));
    expect(restored.aiContext.single.calibrationSampleCount, 0);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey)!;
    expect(raw, isNot(contains('raw_price')));
    expect(raw, isNot(contains('raw_mw')));
    expect(raw, isNot(contains('fcm_token')));
    expect(raw, isNot(contains('latitude')));
    expect(raw, isNot(contains('longitude')));
  });

  test('rejects cache older than eight hours', () async {
    const cache = HydroDispatchCache();
    await cache.save(
      plantId: plantId,
      forecasts: <HydroDispatchDayForecast>[forecastForToday()],
      aiContext: <HydroDispatchAiContext>[aiForToday()],
    );
    final prefs = await SharedPreferences.getInstance();
    final payload = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(cacheKey)!) as Map,
    );
    payload['saved_at'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 9))
        .toIso8601String();
    await prefs.setString(cacheKey, jsonEncode(payload));

    expect(await cache.restore(plantId), isNull);
    expect(prefs.getString(cacheKey), isNull);
  });

  test('rejects previous Romania local day after restart', () async {
    const cache = HydroDispatchCache();
    await cache.save(
      plantId: plantId,
      forecasts: <HydroDispatchDayForecast>[forecastForToday()],
      aiContext: <HydroDispatchAiContext>[aiForToday()],
    );
    final prefs = await SharedPreferences.getInstance();
    final payload = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(cacheKey)!) as Map,
    );
    final rows = (payload['forecasts'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final ro = timezone.getLocation('Europe/Bucharest');
    final yesterday = timezone.TZDateTime.now(ro).subtract(const Duration(days: 1));
    rows.first['delivery_date'] =
        '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    payload['forecasts'] = rows;
    await prefs.setString(cacheKey, jsonEncode(payload));

    expect(await cache.restore(plantId), isNull);
    expect(prefs.getString(cacheKey), isNull);
  });
}
