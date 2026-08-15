import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:fishtrack/services/water_service.dart';
import 'package:fishtrack/widgets/home_premium/water_level_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Home Water truthful presentation rules', () {
    test('formats only finite real deltas', () {
      expect(formatWaterCardDelta(7, 'cm'), '+7 cm');
      expect(formatWaterCardDelta(-2.5, 'cm'), '-2.5 cm');
      expect(formatWaterCardDelta(0, 'cm'), '0 cm');
      expect(formatWaterCardDelta(null, 'cm'), '—');
      expect(formatWaterCardDelta(double.nan, 'cm'), '—');
    });

    test('requires two real observations before rendering a chart', () {
      final now = DateTime.utc(2026, 7, 29, 12);
      final first = WaterLevel(
        stationId: 'station',
        value: 100,
        timestamp: now,
        trend: WaterTrend.stable,
      );
      final second = WaterLevel(
        stationId: 'station',
        value: 104,
        timestamp: now.add(const Duration(hours: 1)),
        trend: WaterTrend.rising,
      );

      expect(shouldShowWaterHistoryChart(const []), isFalse);
      expect(shouldShowWaterHistoryChart([first]), isFalse);
      expect(shouldShowWaterHistoryChart([first, second]), isTrue);
    });

    test('labels sparse real history with its truthful elapsed span', () {
      final now = DateTime.utc(2026, 7, 23, 12);
      final readings = [
        WaterLevel(
          stationId: 'station',
          value: 100,
          timestamp: now,
          trend: WaterTrend.stable,
        ),
        WaterLevel(
          stationId: 'station',
          value: 109,
          timestamp: now.add(const Duration(days: 6)),
          trend: WaterTrend.rising,
        ),
      ];

      expect(
        formatHomeWaterHistoryWindowLabel(readings, isRo: true),
        '144h · 2 măsurători',
      );
      expect(
        formatHomeWaterHistoryWindowLabel(readings, isRo: false),
        '144h · 2 readings',
      );
    });

    test('trend uses distinct semantic colours', () {
      expect(waterCardTrendColor(WaterTrend.rising), const Color(0xFF2196F3));
      expect(waterCardTrendColor(WaterTrend.stable), const Color(0xFF43A047));
      expect(waterCardTrendColor(WaterTrend.falling), const Color(0xFFE53935));
      expect(waterCardTrendColor(null), const Color(0xFF9AA7B2));
    });

    test('LIVE is allowed only for fresh online real data', () {
      bool live({
        bool hasReading = true,
        bool stale = false,
        WaterUiStatus status = WaterUiStatus.availableHistory,
        bool connectivityKnown = true,
        bool offline = false,
      }) => shouldShowWaterLiveBadge(
        hasRealReading: hasReading,
        isStale: stale,
        status: status,
        connectivityKnown: connectivityKnown,
        isDefinitelyOffline: offline,
      );

      expect(live(), isTrue);
      expect(live(hasReading: false), isFalse);
      expect(live(stale: true), isFalse);
      expect(live(status: WaterUiStatus.providerError), isFalse);
      expect(live(connectivityKnown: false), isFalse);
      expect(live(offline: true), isFalse);
    });

    test('daily comparison accepts only a controlled 20–28 hour window', () {
      expect(
        isApproximatelyDailyWaterComparison(const Duration(hours: 24)),
        isTrue,
      );
      expect(
        isApproximatelyDailyWaterComparison(const Duration(hours: -20)),
        isTrue,
      );
      expect(
        isApproximatelyDailyWaterComparison(const Duration(hours: 19)),
        isFalse,
      );
      expect(
        isApproximatelyDailyWaterComparison(const Duration(hours: 29)),
        isFalse,
      );
    });
  });
}
