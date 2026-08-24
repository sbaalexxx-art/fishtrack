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
        '6 zile · 2 măsurători',
      );
      expect(
        formatHomeWaterHistoryWindowLabel(readings, isRo: false),
        '6 days · 2 readings',
      );
    });

    test(
      'axis ticks are bounded, unique by day, and retain interval edges',
      () {
        final start = DateTime.utc(2026, 8, 10, 6);
        final readings = <WaterLevel>[
          for (var day = 0; day < 10; day++) ...[
            WaterLevel(
              stationId: 'station',
              value: 100 + day.toDouble(),
              timestamp: start.add(Duration(days: day)),
              trend: WaterTrend.rising,
            ),
            WaterLevel(
              stationId: 'station',
              value: 100.5 + day,
              timestamp: start.add(Duration(days: day, hours: 6)),
              trend: WaterTrend.rising,
            ),
          ],
        ];

        final narrow = selectHomeWaterChartAxisTicks(readings, chartWidth: 300);
        final wide = selectHomeWaterChartAxisTicks(readings, chartWidth: 358);

        expect(narrow, hasLength(4));
        expect(wide, hasLength(5));
        expect(wide.map((tick) => tick.label).toSet(), hasLength(wide.length));
        expect(wide.first.timestamp, readings.first.timestamp);
        expect(wide.last.timestamp, readings.last.timestamp);
        expect(readings, hasLength(20));
      },
    );

    test('axis labels clamp fully inside both chart edges', () {
      expect(
        homeWaterChartAxisLabelLeft(
          chartWidth: 300,
          labelWidth: 40,
          normalizedPosition: 0,
        ),
        0,
      );
      expect(
        homeWaterChartAxisLabelLeft(
          chartWidth: 300,
          labelWidth: 40,
          normalizedPosition: 1,
        ),
        260,
      );
    });

    testWidgets('rendered date ticks stay inside and do not overlap', (
      tester,
    ) async {
      final start = DateTime.utc(2026, 8, 10, 6);
      final readings = <WaterLevel>[
        for (var day = 0; day < 10; day++)
          WaterLevel(
            stationId: 'station',
            value: 100 + day.toDouble(),
            timestamp: start.add(Duration(days: day)),
            trend: WaterTrend.rising,
            sourceName: 'AFDJ',
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 358,
                height: 140,
                child: HomeWaterHistoryLineChart(
                  readings: readings,
                  color: Colors.blue,
                  unit: 'cm',
                  localeCode: 'ro',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chartRect = tester.getRect(find.byType(HomeWaterHistoryLineChart));
      final labels = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'home-water-axis-',
            ),
      );
      expect(labels, findsNWidgets(5));
      for (final element in labels.evaluate()) {
        expect((element.widget as Text).style!.fontSize, 9.5);
      }
      final rects =
          labels
              .evaluate()
              .map((element) => tester.getRect(find.byWidget(element.widget)))
              .toList()
            ..sort((a, b) => a.left.compareTo(b.left));
      expect(rects.first.left, greaterThanOrEqualTo(chartRect.left));
      expect(rects.last.right, lessThanOrEqualTo(chartRect.right));
      for (var index = 1; index < rects.length; index++) {
        expect(rects[index].left, greaterThanOrEqualTo(rects[index - 1].right));
      }
      expect(tester.takeException(), isNull);
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
