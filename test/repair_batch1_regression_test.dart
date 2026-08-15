import 'package:fishtrack/core/context/selected_context.dart';
import 'package:fishtrack/core/water/water_history_analysis.dart';
import 'package:fishtrack/features/figma_complete/presentation/figma_environment_pages.dart';
import 'package:fishtrack/models/station.dart';
import 'package:fishtrack/models/water_level.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final latest = DateTime.utc(2026, 8, 8, 12);

  List<WaterLevel> history() => [
    _reading(latest.subtract(const Duration(days: 10)), 100),
    _reading(latest.subtract(const Duration(days: 2)), 110),
    _reading(latest.subtract(const Duration(hours: 12)), 115),
    _reading(latest, 120),
  ];

  test('Water history ranges filter real timestamped observations', () {
    expect(
      realWaterHistoryForRange(history(), WaterHistoryRange.hours24).length,
      2,
    );
    expect(
      realWaterHistoryForRange(history(), WaterHistoryRange.days3).length,
      3,
    );
    expect(
      realWaterHistoryForRange(history(), WaterHistoryRange.days30).length,
      4,
    );
  });

  testWidgets('Free Water history changes 24h/3d and locks 30d', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        WaterHistorySheet(history: history(), accessTier: FluviAccessTier.free),
      ),
    );

    expect(find.text('2 observații reale'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('water-history-range-3d')));
    await tester.pump();
    expect(find.text('3 observații reale'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('water-history-range-30d')));
    await tester.pump();
    expect(find.text('3 observații reale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pro Water history exposes the real 30-day range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        WaterHistorySheet(
          history: history(),
          accessTier: FluviAccessTier.premium,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('water-history-range-30d')));
    await tester.pump();
    expect(find.text('4 observații reale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

WaterLevel _reading(DateTime timestamp, double value) => WaterLevel(
  stationId: 'bazias',
  value: value,
  timestamp: timestamp,
  trend: WaterTrend.stable,
  source: WaterLevelSource.afdj,
  sourceName: 'AFDJ',
  hasKnownTrend: true,
);

Widget _app(Widget home) => MaterialApp(
  theme: ThemeData.dark(
    useMaterial3: true,
  ).copyWith(splashFactory: NoSplash.splashFactory),
  home: Scaffold(backgroundColor: const Color(0xFF071216), body: home),
);
